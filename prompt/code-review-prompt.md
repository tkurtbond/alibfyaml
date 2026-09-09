# Comprehensive Review Prompt — alibfyaml

Paste everything below into a fresh session that has this repository checked out
(`/home/cpb/wrk/p/alibfyaml` or wherever you cloned it).

---

You are doing a comprehensive, multi-dimensional review of **alibfyaml**, a pure-Ada
binding to the C library **libfyaml** (targeting its 1.0-beta1 API), built via
`Interfaces.C` imports — no C headers are compiled, only linked against.

Read `README.md` and `PLAN.md` first for design intent and known trade-offs before
reviewing anything else. Then review these files, in this order (low-level binding
outward to consumers):

1. `src/libfyaml-thin.ads` — raw `Interfaces.C` imports, 1:1 mirror of the C API
2. `src/libfyaml.ads` — exception types (`Parse_Error`, `Emit_Error`)
3. `src/libfyaml-nodes.ads` / `.adb` — `Node`: non-owning handle, predicates,
   scalar/sequence/mapping access, path lookup
4. `src/libfyaml-documents.ads` / `.adb` — `Document`: RAII (controlled) owner of a
   parsed/built tree
5. `src/libfyaml-documents-streams.ads` / `.adb` — `Document_Stream`: multi-document
   streaming parse (built on `fy_parser_create` + `fy_parse_load_document`, distinct
   code path from the single-document build API)
6. `test/*.adb` — read these *last*, then cross-check: do they actually exercise the
   claims made in README.md/PLAN.md, or just the happy path?

For each dimension below, cite the specific file and line. Don't restate what the
code obviously does — say what's wrong, risky, or inconsistent, and why it matters
concretely (a scenario, not a vague "could be an issue").

## 1. Correctness & FFI/memory safety (primary focus)

This is a hand-written binding over a C library with its own ownership model, so
weight this dimension heaviest.

- **Ownership/lifetime**: For every `Interfaces.C` import in `libfyaml-thin.ads`,
  trace who owns the returned pointer/string and who is responsible for freeing it.
  Cross-check against libfyaml's actual contract (check the installed
  `libfyaml.h`/`libfyaml-*.h` headers, or the upstream source at
  https://github.com/pantoniou/libfyaml if not locally checked out) — not just what
  the Ada comment claims.
- **Controlled type discipline**: `Document` is RAII via `Ada.Finalization`. Verify
  `Initialize`/`Adjust`/`Finalize` are all correct together — specifically: does
  copying a `Document` (`Adjust`) do the right thing given libfyaml's document is a
  single owned tree (deep copy? refcount? or should copying be forbidden and isn't)?
  Is `Finalize` idempotent (safe if called twice, e.g. via an exception during
  construction)? Any path where an exception between `fy_document_build_*` succeeding
  and the controlled object being fully initialized would leak the C-side document?
- **Non-owning `Node` handles**: `Node` is described as a "cheap, non-owning handle."
  Confirm there's no way to hold a `Node` past its owning `Document`'s lifetime that
  the Ada type system doesn't catch (dangling access) — is this only a documented
  discipline, or is anything enforced? Say which.
- **String marshalling**: every `String` ↔ `chars_ptr`/`char_array` conversion —
  confirm proper null-termination, no leaked `New_String`/`To_C` allocations, correct
  handling of libfyaml strings that are *not* null-terminated (libfyaml often returns
  `(pointer, length)` pairs rather than C strings — check whether this binding
  correctly uses the length rather than assuming NUL-termination, which would
  truncate on embedded content or over-read on non-terminated buffers).
- **Error-code → exception mapping**: does every libfyaml failure return get checked,
  or are there C calls whose failure is silently ignored (a NULL return treated as
  success, a negative return code not tested)?
- **Exception safety**: are `Parse_Error`/`Emit_Error`/`Missing_Key`/`Data_Error`
  raised at points that leave no partially-constructed/leaked C state behind?
- **Numeric parsing extensions** (`0b` binary, `_` digit separator in
  `libfyaml-nodes.adb`): these are hand-rolled parsers per README — check them
  directly for off-by-one errors, integer overflow handling (does it detect overflow
  correctly and consistently across `Integer_Value`/`Long_Integer_Value`/
  `Long_Long_Integer_Value`?), and that the "single underscore, strictly between two
  digits" rule is actually what's implemented (test the boundary cases: leading,
  trailing, doubled, adjacent to a sign or decimal point).
- **`Document_Stream`**: PLAN.md apparently documents "two lifetime bugs found and
  fixed" during development of this — re-derive whether the *fix* is actually
  correct and complete, not just whether it matches the bug that was fixed. Look
  specifically for: parser/document lifetime across repeated `fy_parse_load_document`
  calls, and cleanup on the mid-stream-parse-error path (does a `Parse_Error` raised
  partway through leak the underlying `fy_parser`?).

## 2. API design & Ada idioms

- Naming and casing conform to Ada conventions consistently across the public specs.
- Encapsulation: are `Interfaces.C` types and raw pointers ever leaked through the
  public API of `Libfyaml.Nodes`/`Libfyaml.Documents`, or fully hidden behind the
  `thin` layer?
- Is the required-vs-optional-with-default accessor split (`Integer_Value`,
  `Missing_Key`/`Data_Error` semantics) applied consistently across all typed scalar
  accessors, or do one or two of them deviate?
- Any place where the Ada API is a thinner-than-necessary wrapper that just
  reproduces C awkwardness (e.g., sentinel returns, manual index math) instead of
  using Ada's type system (exceptions, `Boolean` predicates, discriminants)?
- Consistency of `Long_Long_Integer_Value`/`Long_Float_Value` "widened" variants with
  their base forms — same rounding/overflow behavior, or silently different?

## 3. Test coverage & edge cases

Map `test/*.adb` against `src/` and name concrete gaps — not "add more tests" in the
abstract, but specific missing cases:

- Which public subprograms in `libfyaml-nodes.ads`/`libfyaml-documents.ads`/
  `libfyaml-documents-streams.ads` have **zero** direct test coverage?
- Error paths: for each exception type, is there at least one test that actually
  triggers it (not just documents it should be raised)?
- `Document_Stream` mid-stream error test (`test_streams.adb`) — does it test that
  the stream/parser is left in a *usable* state to detect the error, and that
  resources are cleaned up, not just that the exception fires?
- Numeric-extension edge cases from PLAN.md's design (`0b`, `_` separator) — are all
  the documented boundary rules (leading/trailing/doubled underscore, mixed with
  hex/octal/exponent) actually covered in `test_scalars.adb`/`scalars.yaml`, or only
  a subset?
- Any test that depends on iteration/map key order that libfyaml doesn't guarantee
  (fragile test, not a real assertion)?
- Multi-document stream test: empty stream, single-document stream (boundary of
  "stream" vs "single document"), stream ending mid-document (truncated input, not
  just malformed).

## 4. Docs & spec accuracy

- Walk every claim in `README.md`'s "Scope", "Typed scalar accessors", and "Multi-
  document YAML streams" sections against the actual code — flag anything now stale
  (e.g., function lists, exception names, extension rules) given the most recent
  commits (`git log --oneline -10`).
- `PLAN.md` — does it still reflect the implemented design, or are there resolved
  TODOs/open questions in it that the code has since settled one way and the doc
  wasn't updated?
- `000-todo.org` at repo root — cross-check against current `src/` to see if any
  listed item is actually already done (stale todo) or if the code has drifted from
  what the todo assumes.
- Doc comments in `.ads` files: any that describe behavior the `.adb` doesn't
  actually implement (aspirational comments), or vice versa (implemented behavior
  that's undocumented and non-obvious, e.g. a silent clamping/truncation).

## Output format

Write the full review to `REVIEW.md` in the repository root (create it if absent,
overwrite if present), in addition to summarizing it in your reply. Structure the
file as:

```markdown
# alibfyaml Code Review — <date>

Reviewed at commit <git rev-parse --short HEAD>.

## Summary

<2-4 sentences: overall health, and the single most important finding, if any>

## 1. Correctness & FFI/memory safety

### <file>:<line> — <one-line summary>
- **Severity**: blocker | major | minor | nit
- **Scenario**: <concrete input/sequence that triggers it, or "N/A — design/doc issue">
- **Fix**: <specific suggested change, or "needs discussion" if a real trade-off>

<repeat per finding, most severe first; if none, write "No findings.">

## 2. API design & Ada idioms
<same structure>

## 3. Test coverage & edge cases
<same structure>

## 4. Docs & spec accuracy
<same structure>

## What's solid

<short, honest note on what doesn't need changing — don't manufacture issues to
fill a quota; if a dimension above has no real findings, say so plainly there
rather than padding it with nits>
```
