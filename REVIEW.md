# alibfyaml Code Review — 2026-09-09

Reviewed at commit `474f1a9` ("Decide against binding YAML 1.1 extra types").

Method: read every file in `src/`, `README.md`, `PLAN.md`, and `000-todo.org`;
cross-checked claims against libfyaml's own installed headers (built from
upstream `pantoniou/libfyaml` HEAD, 1.0.0-beta1); and empirically verified two
of the findings below by compiling and running small standalone Ada programs
against this binding and a local libfyaml build (see "Evidence" notes).

## Summary

The binding is careful and mostly correct where it matters most — buffer
lifetime across the Ada/C boundary (the exact area PLAN.md records two past
bugs in) is handled right in every path reviewed, and the hand-rolled numeric
extension parser is sound on everything the test suite drives it with. Two
gaps undercut the safety story the API's `Pre =>` contracts are supposed
to provide: the project's own `.gpr` files never enabled `-gnata`, so those
contracts compiled away to nothing (confirmed to produce three different kinds
of silent misbehavior, including an unhandled crash, on the exact same
invalid input); and `Document_Stream` permanently misreported every document
after the first parse error, confirmed live.

**Every finding in this review is now fixed** — the three correctness
findings in §1, and every API-design/test-coverage/docs finding below them.
See each entry for what changed, including three corrections made to my own
first write-up along the way as the fixes were verified empirically rather
than assumed from the C headers alone: full `Document_Stream` *resumption*
past a bad document turned out to be blocked by libfyaml itself, not
fixable from this binding — the fix makes the failure honest, not
recoverable; `Insert_At`'s node-draining turned out to reach the plain
scalar-overwrite case too, not just sequence/mapping merges as originally
scoped; and `Set_Root`/`Append`/`Append_Pair` were confirmed (not just
assumed from their headers) to leave their node arguments valid and intact,
unlike `Insert_At`.

## 1. Correctness & FFI/memory safety

### src/libfyaml_ada.gpr:11-12, test/test.gpr:15 — `Pre =>` contracts are silently unenforced; demonstrated three divergent unsafe behaviors on the same invalid input
- **Status**: fixed. `-gnata` added to `Default_Switches ("Ada")` in both
  `libfyaml_ada.gpr` and `test/test.gpr`, with a comment on each pointing at
  the other. The full test suite (all five `test/*.adb` programs) still
  passes cleanly with assertions on, confirming no latent precondition
  violation elsewhere in `src/` was hiding behind this gap. The README's
  Building section didn't need a change: the library itself now enables
  `-gnata`, so a consumer building `libfyaml_ada.gpr` normally gets the
  contracts for free rather than needing to know to add the switch.
- **Severity**: blocker
- **Scenario**: `Libfyaml.Nodes` declares `Pre => Is_Valid (N)` (and further
  shape preconditions) on nearly every primitive — `Kind`, `Scalar_Value`,
  `Integer_Value`, `Length`, `Item`, etc. Neither `libfyaml_ada.gpr` nor
  `test/test.gpr` passes `-gnat​a` (or otherwise enables assertion checking),
  so none of these contracts are checked at runtime in the configuration
  this repo actually builds and tests with. I compiled a throwaway program
  against the built library and called three different primitives on
  `Nodes.Null_Node` (an `Is_Valid (N) = False` handle, i.e. a direct
  precondition violation):
  - `N.Kind` returned `SCALAR_NODE` — a plausible-looking but meaningless
    answer, not an error. (This traces to libfyaml's own documented
    behavior: `fy_node_get_type()`'s header comment says "A NULL node
    argument is a FYNT_SCALAR" — a real, intentional C-level convenience
    that the Ada `Pre` contracts exist specifically to keep from ever
    reaching an Ada caller. With `-gnata` off, it reaches them anyway.)
  - `N.Scalar_Value` returned `""` — again valid-looking, indistinguishable
    from a real empty-string scalar.
  - `N.Length` raised an *unhandled* `CONSTRAINT_ERROR : libfyaml-nodes.adb:339
    range check failed` — a hard crash, from converting `libfyaml`'s -1
    ("not a sequence/mapping") into `Natural`.

  Any caller of this binding who has a latent bug that violates one of
  these preconditions (a very real risk in hand-written tree-walking code)
  gets one of these three inconsistent outcomes instead of a clean,
  catchable Ada exception — in the exact build the project ships.
- **Fix**: add `-gnata` to `Default_Switches ("Ada")` in both
  `libfyaml_ada.gpr` and `test/test.gpr` (at minimum for the test build;
  ideally for the library too, since consumers who build with `gprbuild -P
  libfyaml_ada.gpr` and don't add their own `-gnata` get the same gap). Note
  this in the README's Building section so consumers linking against a
  `-gnata`-less build of the library know the contracts aren't load-bearing.

### src/libfyaml-documents-streams.adb:92-108 — a `Document_Stream` permanently misreports every later document as a parse error, after any one parse error
- **Status**: fixed, with a corrected scope worth recording. `Fetch` now
  swaps in a brand new `Diag` (via a new `fy_parser_set_diag` binding)
  whenever it raises `Parse_Error`, so the sticky `fy_diag_got_error` flag
  and the cumulative `fy_diag_errors_iterate` list can never again leak
  into a later, unrelated `Fetch` call. Verified live: `Has_Next` after the
  error now returns a clean `False` instead of raising `Parse_Error` again.

  However, chasing this further (via `fy_parser_reset`, tried directly
  against the C API) turned up that the premise "the stream can be resumed
  past the bad document" in my original write-up below was wrong:
  libfyaml's streaming parser cannot resync mid-stream after a malformed
  document at all — even an explicit `fy_parser_reset` leaves it reporting
  "out of tokens and failed to produce anymore," not usable input state.
  So a well-formed document *after* a malformed one in the same stream is
  genuinely unreachable, independent of this bug; that's an upstream
  libfyaml streaming-API limitation, not something fixable from this
  binding. The fix's actual, narrower scope: a `Document_Stream` no longer
  lies about *why* it stopped (a stale duplicate error instead of an
  honest clean end) — it does not gain the ability to skip a bad document
  and keep going. `test_streams.adb`, `libfyaml-documents-streams.ads`, and
  the README's "Multi-document YAML streams" section were all updated to
  state this limitation plainly instead of the original, incorrect
  "distinct from a clean end of stream" framing implying resumability.
- **Severity**: major
- **Scenario**: `Fetch` treats `Fyd = Null_Fy_Document and then
  fy_diag_got_error (Stream.Diag)` as "this NULL means a parse error, not a
  clean end of stream." But `fy_diag_got_error` is a *sticky* flag — per
  libfyaml's own header, it is only cleared by `fy_diag_reset_error()`,
  which this binding never calls; and `fy_diag_errors_iterate` (used to
  build the exception message) "iterates over all the errors collected on
  the diagnostic object" — also cumulative, never cleared. Since
  `Document_Stream` deliberately keeps one `Diag` alive for the whole
  stream (by design, per the comment at
  `libfyaml-documents-streams.ads:63-67`), once *any* document in the
  stream fails to parse, `Stream.Diag`'s error flag stays set forever.
  I confirmed this live: a 3-document stream where document 2 is malformed
  and document 3 is perfectly valid —
  ```
  doc1 name = ok
  doc2: Parse_Error (expected) msg=[...: missing comma in flow sequence]
  --- now checking doc3 (should be a clean valid document) ---
  doc3: Parse_Error RAISED (this is the suspected bug) msg=[...: missing comma in flow sequence]
  ```
  Document 3 is well-formed YAML, yet `Has_Next`/`Next` raises
  `Libfyaml.Parse_Error` again, quoting document 2's now-stale message.
  A caller who catches the first `Parse_Error` to skip one bad document and
  keep reading the rest of the stream — the natural and, per the README's
  own framing ("distinct from `Has_Next` returning `False` at a clean end
  of stream"), reasonably expected use of this exception — cannot do so:
  the stream is permanently poisoned.
- **Fix**: call `Thin.fy_diag_reset_error` (needs binding in
  `libfyaml-thin.ads`) after handling a `Parse_Error` in `Fetch`, or
  document clearly that a `Document_Stream` must be abandoned after its
  first `Parse_Error` and cannot be resumed — and either way, add the
  resume-after-error test case this would have caught (see §3, H1).

### src/libfyaml-documents.adb:114-124 — `Insert_At` can leave the caller holding a dangling `Node` on the failure path
- **Status**: fixed, and widened along the way. `Insert_At`'s `N` parameter
  is now `in out`; on failure it's set to `Nodes.Null_Node` before
  `Program_Error` propagates, so a caught failure can never leave the
  caller touching freed memory — confirmed live before the fix
  (`Scalar_Value` on the freed node silently returned `""` instead of its
  real content instead of failing loudly) and confirmed after (the same
  scenario now reports `Is_Valid = False`, and with the `-gnata` fix from
  earlier, any further precondition-checked use of it raises
  `Assertion_Error` instead of touching freed memory).

  Empirically probing the *success* path to decide the fix's scope turned
  up something broader than originally scoped here: `N`'s content can be
  silently detached from what ends up attached at `Path` even on success —
  not only for the sequence/mapping-merge case this entry originally
  described, but for a plain scalar-overwrites-scalar replacement too
  (confirmed: replacing an existing scalar left `N.Scalar_Value` no longer
  reading back what was built, even though the right value was correctly
  attached at `Path`). `N` is *not* nulled out on success, though — unlike
  the failure path, the underlying node object is genuinely still alive
  there (`Is_Valid` stays true, confirmed no crash/corruption touching it),
  just possibly emptied; forcing it to `Null_Node` would be inaccurate for
  the (also real, and tested) case where `N` is attached outright with no
  merge involved. The doc comment on `Insert_At` states this precisely: on
  success, `N` stays valid and safe to touch, but never assume it still
  holds what it held before the call — re-fetch via `By_Path` instead. A
  new `test/test_mutate.adb` pins down all three outcomes (attach, merge,
  and the failure/null case) with `Check`-style assertions.
- **Severity**: major
- **Scenario**: libfyaml's own header for `fy_document_insert_at` is
  explicit: "Note that in any case the fyn node will be unref'ed. So if the
  operation fails, and the reference is 0 the node will be freed." On
  success this is benign sink semantics (the tree now owns the node,
  matching `Set_Root`/`Append`/`Append_Pair`, none of which document this
  unref). On **failure**, though, a freshly-built, not-yet-attached node
  (the normal case for `Insert_At`'s documented usage — "typically freshly
  built via `Create_Scalar`/`_Sequence`/`_Mapping`") has no other owner, so
  its refcount drops to 0 and libfyaml frees it — while
  `Libfyaml.Documents.Insert_At` only raises `Program_Error`; it does not,
  and structurally cannot (the caller's `Node` is a separate copy of the
  handle), invalidate the caller's `N`. A caller that catches the
  `Program_Error` and then inspects, retries with, or logs `N` (e.g.
  `N.Scalar_Value`) touches freed memory.
- **Fix**: document this explicitly on `Insert_At` (mirroring the header's
  own wording: *N is always invalidated by this call, on success or
  failure; do not use it afterward*), and audit call sites/examples for the
  retry-on-failure pattern this would silently break.

### src/libfyaml-documents.adb:34-63 — `Diag` could leak if `Build` itself raised (defense-in-depth note)
- **Status**: fixed. `Parse_Common` now has an `exception when others =>
  fy_diag_destroy (Diag); raise;` handler around the whole body.
- **Severity**: nit
- **Scenario**: `Parse_Common` has no exception handler around the `Build
  (Cfg'Access)` call; if it propagated an Ada exception, `Diag` would never
  be destroyed. In practice `Build` is a direct `Interfaces.C` import call
  that cannot raise an Ada exception under normal operation, so this is
  near-theoretical.
- **Fix**: not urgent; a defensive `exception when others => fy_diag_destroy
  (Diag); raise;` would close the gap for free if ever touched.

### src/libfyaml-nodes.ads:104-106, .adb:343-348 — `Item` silently returns `Null_Node` outside its documented range
- **Status**: fixed. Doc comment reworded to state the actual behavior
  (`Null_Node` on an out-of-range `Index`, libfyaml's own behavior passed
  through) instead of a range that was never enforced.
- **Severity**: minor
- **Scenario**: the doc comment says "Index must be in 1 .. Length (N)" but
  nothing enforces or documents what happens otherwise. In practice it's
  safe (libfyaml's `fy_node_sequence_get_by_index` returns NULL for an
  out-of-range index rather than crashing, and negative indices — which
  `Item`'s `Positive` parameter type can't even produce — mean "from the
  end" upstream), but the doc comment reads as a hard contract it doesn't
  enforce, inconsistent with how strictly the rest of the API's `Pre =>`
  clauses are worded.
- **Fix**: reword the doc comment to state the actual behavior ("returns
  `Null_Node` if Index exceeds Length(N)") rather than a range that isn't
  enforced.

## 2. API design & Ada idioms

### src/libfyaml-nodes.adb:197-204 — `Is_Scalar`/`Is_Sequence`/`Is_Mapping`/`Kind` each make an independent C call
- **Status**: fixed. All three are now expressed in terms of `Kind`
  (`Is_Scalar (N) is (Kind (N) = Scalar_Node)`, etc.), one
  `fy_node_get_type` call instead of two.
- **Severity**: nit
- **Scenario**: each predicate calls `Thin.fy_node_get_type` separately
  rather than being expressed in terms of `Kind`, or vice versa. No
  correctness impact, just a redundant FFI round-trip in tree-walk-heavy
  code (e.g. `Iterate` callers checking shape per element).
- **Fix**: express the three predicates in terms of `Kind`, e.g. `Is_Scalar
  (N) is (Kind (N) = Scalar_Node)`.

### src/libfyaml-documents.ads:46-57 — node-consuming semantics aren't documented for any of the tree-mutation entry points
- **Status**: fixed. `Set_Root`, `Append`, and `Append_Pair` now each carry
  a one-line ownership note, confirmed empirically (not just from the
  header text): all three leave their node argument(s) valid and reading
  exactly what was built, unlike `Insert_At`. `Insert_At` itself was
  already covered by its own fix above.
- **Severity**: minor
- **Scenario**: as found in §1 (`Insert_At`), libfyaml has specific,
  per-function ownership-transfer rules for node arguments passed into
  tree-attach calls. None of `Set_Root`, `Insert_At`, `Append`, or
  `Append_Pair`'s doc comments say anything about whether/when the `Node`
  arguments they take remain valid to use afterward — a caller has to go
  read the C headers to know.
- **Fix**: add a one-line ownership note to each of these four doc comments,
  even where the answer is simply "still valid, now owned by the tree."

## 3. Test coverage & edge cases

### test/test_streams.adb — no test resumes a `Document_Stream` after a `Parse_Error`
- **Status**: fixed. The bad-stream test block now includes a third,
  well-formed document after the malformed one and calls `Has_Next` again
  after catching the first `Parse_Error`, asserting it returns `False`
  (clean end) rather than raising a second time. All `test_streams.adb`
  checks pass.
- **Severity**: major
- **Scenario**: the existing "bad stream" test stops immediately after
  asserting the first `Parse_Error` fires; it never calls `Has_Next`/`Next`
  again afterward. This is exactly the gap that let §1's `Document_Stream`
  bug through — a follow-up `Has_Next` call after the caught exception
  would have caught it directly.
- **Fix**: extend the existing bad-stream test block to call `Has_Next`
  again after catching the first `Parse_Error` and assert on what happens
  (today: another spurious `Parse_Error`, quoting stale text).

### test/test.gpr, libfyaml_ada.gpr — no build anywhere enables `-gnata`
- **Status**: fixed alongside §1's blocker finding — see there.
- **Severity**: minor
- **Scenario**: ties directly to §1's blocker finding — with `-gnata` never
  enabled in either project file, the extensive `Pre =>` contracts across
  `Libfyaml.Nodes` are never exercised *as contracts* by this repo's own
  test suite, not even once. A future precondition violation introduced
  anywhere in `src/` would compile and link cleanly and only surface as
  unpredictable runtime behavior, exactly as demonstrated in §1.
- **Fix**: enable `-gnata` in `test/test.gpr` at minimum; see §1's fix note
  for the library project too.

### test/test_navigate.adb — no pass/fail assertions
- **Status**: fixed. A "Regression checks" section (`Check`/`Failures`,
  same pattern as the other tests) was added at the end, spot-checking a
  handful of the values the walkthrough above already prints, at each
  depth demonstrated. The walkthrough itself is untouched, so it still
  reads as a worked example rather than being restructured into
  assertions throughout.
- **Severity**: minor
- **Scenario**: by design (per README: "a worked example of tree
  navigation, not a pass/fail test") it only prints output; a regression
  here (e.g. `By_Path` silently starting to return the wrong node) would
  not fail a CI run — only a human diffing console output would notice.
- **Fix**: either add `Check`-style assertions matching the other four
  tests' pattern, or explicitly diff its output against a committed golden
  file in CI.

### test/scalars.yaml, test_scalars.adb — `Long_Long_Integer_Value`/`Long_Float_Value` overflow paths untested
- **Status**: fixed. `scalars.yaml` gained `huge_int` (exceeds even 64-bit)
  and `huge_float` (`1.0e400`, exceeds `Long_Float`), each asserted to
  raise `Data_Error` from the corresponding widest accessor.
- **Severity**: nit
- **Scenario**: the suite tests `Integer_Value`/`Float_Value` overflow
  (`big_int`, `float_overflow`) on values chosen to overflow only the
  *narrower* type while still fitting the wider `Long_*`/`Long_Long_*`
  forms — by design, to prove the wider accessors succeed where the
  narrower ones raise. But nothing drives `Long_Long_Integer_Value` or
  `Long_Float_Value` to their own actual overflow boundary, so that
  `Data_Error` path in each is never exercised.
- **Fix**: add a value like `99999999999999999999` (exceeds 64-bit) and
  assert `Long_Long_Integer_Value` raises `Data_Error`.

### test/scalars.yaml — no sign+prefix combination tested
- **Status**: fixed. `scalars.yaml` gained `int_hex_neg: -0x1A`, asserted
  to equal `-26`.
- **Severity**: nit
- **Scenario**: `int_hex`/`int_oct`/`int_bin` are all tested unsigned only;
  `int_neg` is tested only in plain decimal. `Strip_Sign`/`Integer_Literal_Text`
  in `libfyaml-nodes.adb` handle a sign before `0x`/`0o`/`0b` (e.g.
  `-0x1A`), but no test drives that combined path.
- **Fix**: add e.g. `int_hex_neg: -0x1A` to `scalars.yaml` and assert.

### test/streams.yaml, test_streams.adb — no empty-stream or exactly-one-document-stream test
- **Status**: fixed. Two new blocks added to `test_streams.adb`: an
  `Open_String ("")` stream asserted to report `Has_Next = False`
  immediately, and a single-document `Open_String` stream asserted to
  yield exactly one document with the right content.
- **Severity**: minor
- **Scenario**: all `Document_Stream` tests use 2- or 3-document input.
  The boundary between "no documents" (`Has_Next` false immediately) and
  "exactly one document" (matches what `Parse_String`/`Parse_File` would
  also produce, but through the streaming path) is untested.
- **Fix**: add both cases as small `Open_String` tests.

## 4. Docs & spec accuracy

### README.md:91-121 "Multi-document YAML streams" — doesn't document the post-error stream-poisoning behavior
- **Status**: fixed. The section now has an explicit "A stream does not
  recover from a parse error" paragraph, stating both what was fixed
  (`Has_Next` no longer raises a second, stale `Parse_Error`) and what
  wasn't and isn't fixable from this binding (a well-formed document past
  a malformed one in the same stream is genuinely unreachable — a
  libfyaml streaming-API limitation, confirmed directly against the C
  library).
- **Severity**: major
- **Scenario**: the section states a parse error "raises
  `Libfyaml.Parse_Error`, distinct from `Has_Next` returning `False` at a
  clean end of stream" — true as far as it goes, but silent on what happens
  if the caller keeps using the stream afterward, which per §1 is currently
  broken (every later document, however valid, also raises `Parse_Error`).
  A reader has no way to know this without hitting it.
- **Fix**: once §1 is fixed, document that a stream recovers after an error;
  until then, explicitly document that a `Document_Stream` must be
  abandoned after its first `Parse_Error`.

### README.md "Building" — doesn't mention `-gnata` at all
- **Status**: fixed alongside §1's blocker finding — see there (resolved by
  enabling `-gnata` in the shipped `.gpr`, so no README change was needed
  beyond that, as this finding's own Fix note anticipated).
- **Severity**: major
- **Scenario**: given how much of `Libfyaml.Nodes`'s documented safety
  contract rests on `Pre =>` clauses, and given neither project file turns
  assertion checking on (§1), the README should say so — right now a
  reader has no signal that these preconditions are decorative unless they
  read the `.gpr` files themselves.
- **Fix**: add a line to the Building section once §1 is addressed (or, if
  addressed by enabling `-gnata` in the shipped `.gpr`, no doc change is
  needed beyond that).

### src/libfyaml-documents.ads:50-52 `Insert_At` — doesn't mention the node-consuming semantics found in §1
- **Status**: fixed alongside §1's `Insert_At` finding — see there.
- **Severity**: minor
- **Scenario**: see §1's `Insert_At` finding — the doc comment should carry
  the same ownership warning libfyaml's own header states plainly.
- **Fix**: covered by §1's fix.

### 000-todo.org:47-59 — the open zero-copy question about mapping-key lifetime is answerable now, and the answer is "safe"
- **Status**: fixed. `000-todo.org` updated in place: both the mapping-key
  and the `Insert_At`-path sub-questions marked RESOLVED (both safe to
  free immediately, for the same reason), with a cross-reference to
  `Insert_At`'s real (different) lifetime hazard and its fix.
- **Severity**: nit (informational, not a defect)
- **Scenario**: the TODO asks whether `Value`'s (and `Has_Key`/`Required`'s)
  immediate `CS.Free (C_Key)` after
  `fy_node_mapping_lookup_value_by_string` is safe, given libfyaml's
  zero-copy tendencies elsewhere. Checking the upstream header: this
  function's key parameter doc says "The YAML source to use as key" and
  the function description says the lookup is "from the YAML node *created
  from* the @key argument" — i.e. the key text is parsed into a transient
  node for comparison during the call, not retained afterward. The current
  code (free immediately after the call) is correct as-is.
- **Fix**: mark this sub-question resolved in `000-todo.org`; the
  `Insert_At`-path sub-question in the same TODO item remains open, and
  should now additionally reference §1's `Insert_At` finding above, which
  answers it (unfavorably — `Insert_At` *does* have a real ownership
  hazard, just of the target node, not of the path string it also asked
  about; the path string itself is copied by libfyaml before use and is
  safe to free immediately, same reasoning as the key case here).

## What's solid

- **No copy-semantics/double-free surface at all**: both `Document` and
  `Document_Stream` are `Ada.Finalization.Limited_Controlled`, so there's
  no `Adjust` to get right (or wrong) — the entire class of "what does
  copying an RAII handle onto a C resource mean" bugs is structurally
  impossible here, not just carefully handled.
- **`Scalar_Value` correctly handles libfyaml's non-NUL-terminated scalar
  spans**: it uses the length-aware `Interfaces.C.Strings.Value (Ptr, Len)`
  overload, not the NUL-terminated one — exactly right for libfyaml's
  pointer+length scalar representation, and resolves what `000-todo.org`
  flags as an open risk area.
- **The two buffer-lifetime bugs PLAN.md records as already found and
  fixed** (`Parse_String`'s input buffer, `Open_File`'s filename) are
  correctly fixed as implemented: each owned buffer is freed exactly once,
  in `Finalize`, only after ownership has unambiguously transferred, with a
  matching `exception when others => ... Free ... raise;` guard on every
  construction path that can fail before that transfer happens.
- **No `Interfaces.C` type ever leaks through the public specs** of
  `Libfyaml.Nodes` or `Libfyaml.Documents` — the `Thin` layer is fully
  contained to package bodies, exactly as `README.md`'s Layout section
  describes.
- **The required-vs-optional-with-default split is complete and
  consistent** across all seven typed scalar accessors, including the "a
  `Default` only substitutes for absence, never for a shape error" rule —
  and `test_scalars.adb` specifically exercises that exact rule
  (`Boolean_Value (not_scalar, default)` still raises `Data_Error`).
- **The `0b`/`_` numeric-extension parser is sound** on every case the
  test suite drives it with — I re-derived `Digit_Run_Length`'s
  underscore-placement grammar by hand against `libfyaml-nodes.adb` and
  found no off-by-one in acceptance or rejection for any tested input.
