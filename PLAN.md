# Typed scalar accessors, timestamps, and document resolution for alibfyaml

## Motivation

libfyaml's core API — the layer `alibfyaml` binds — deliberately hands
back scalar content as text (`fy_node_get_scalar`/`Scalar_Value`). Is
`"8"` an integer, is `"true"` a boolean, is `"3.5"` a float — none of
that is resolved by the C library; it's left to the caller. Implicit
typing of scalars lives in libfyaml's *generics* layer (`fy_generic`),
which `alibfyaml` doesn't bind (its ergonomic constructors are C11
`_Generic`/variadic macros with no C-callable equivalent — see
`src/libfyaml.ads`).

(`fy_node_is_null`/`Is_Null_Value` looked at first like a real
core-layer exception to this — turned out not to be, once actually
implemented and tested against literal `~`/`null` text: libfyaml's
`fy_node_is_null` only catches a genuinely *empty/omitted* scalar,
e.g. `key:` with nothing after it, which is unambiguous at the
grammar level regardless of schema. It does not recognize the literal
text `~`/`null`/`Null`/`NULL` as null — that resolution had to be
added on the Ada side too, the same as everything else here.)

"Give me this mapping value as an `Integer`" is a generically useful
binding feature that any consumer parsing typed data out of YAML will
want, not something worth leaving to each caller to reinvent.

Scope broadened after a follow-up question ("does alibfyaml support all
the YAML data types and values: dates and timestamps, etc?"), which
turned up two more gaps worth fixing at the same time: no way to parse
YAML timestamps, and a currently-silent mishandling of anchors, aliases,
and merge keys. Both are folded into this plan below rather than
tracked separately, since they're all instances of the same underlying
theme — closing the gap between "libfyaml hands back inert text/tree
structure" and "the caller gets the value they actually meant."

## Design goals

- Implement YAML 1.2 **core schema** scalar resolution for the types
  that schema defines (null, bool, int, float), as plain Ada functions
  over `Node`/`Scalar_Value` — no change to the underlying C binding.
- Fold in the "required key" / "optional key with default" pattern
  that typed access needs anyway, so a hand-rolled `Must_Integer`/
  `May_Integer` pair isn't something every consumer writes for itself.
- Keep failure modes distinct and explicit: a **missing** key is not
  the same problem as a **malformed** value, and callers need to tell
  them apart (an optional field defaults cleanly if absent, but should
  still raise if present-and-garbage).
- Non-breaking, additive change to the existing `Libfyaml.Nodes` API.
- Timestamps: implement entirely in Ada. libfyaml has **no** timestamp
  concept anywhere — confirmed by `grep -ri timestamp` across the whole
  libfyaml source tree (zero hits) and by `fy_generic_type`'s full
  member list (`NULL, BOOL, INT, FLOAT, STRING, SEQUENCE, MAPPING,
  INDIRECT, ALIAS` — no date/time variant). So this is explicitly a
  beyond-core-schema, `alibfyaml`-only convenience, not a binding to
  anything libfyaml itself does.
- Anchors/aliases/merge keys: stop the current silent-wrong-data
  behavior (see the dedicated section below) — this is a correctness
  fix, not just an API addition.

## Scope: which types, which schema rules

YAML 1.2's core schema (https://yaml.org/spec/1.2.2/#103-core-schema)
resolves untagged plain scalars as:

| Type | Accepted forms |
|---|---|
| Null | `""`, `~`, `null`, `Null`, `NULL` |
| Bool | `true`/`True`/`TRUE`, `false`/`False`/`FALSE` |
| Int | optional `+`/`-`, decimal; `0x`/`0o` hex/octal (core schema extension) |
| Float | decimal with optional exponent; `.inf`/`-.inf`/`.nan` (and case variants) |

Proposed v1 scope:

- **Boolean**: `true`/`false` and their `True`/`TRUE`/`False`/`FALSE`
  case variants only. *Not* in scope: YAML 1.1-style `yes`/`no`/`on`/
  `off` — those aren't in the 1.2 core schema and libfyaml targets
  1.2/JSON, so accepting them would be inventing a laxer schema than
  the format itself defines. Open question below in case a consumer
  needs them.
- **Integer**: decimal, with `0x`/`0o` accepted per core schema, plus
  two deliberate extensions beyond core schema (documented in
  README.md, not silently added): `0b` binary (a YAML 1.1 form, not
  1.2 core schema — libfyaml's own generics layer, which this binding
  doesn't cover, only accepts it under an explicit YAML 1.1 schema
  selection), and `_` as a digit separator in any base, accepted only
  strictly between two digits (matching Ada's own numeral syntax,
  which is also how the implementation gets this for free —
  underscores pass straight through to `Integer'Value` and friends).
  Provide `Integer`, `Long_Integer`, and `Long_Long_Integer` accessors
  — all three, not just `Integer`/`Long_Long_Integer`, since a general
  binding shouldn't force every caller needing more than 32 (or fewer
  than 64) bits to convert by hand, and `Long_Integer` is the type
  GNAT/most platforms actually use for "the wider native int."
- **Float**: decimal + exponent form. `.inf`/`-.inf`/`.nan` deferred to
  an open question (rare in practice; easy to add later without an API
  break).
- Null resolution is `Is_Null_Value` (see the Motivation correction
  above: this needed a real Ada-side fix too, not just libfyaml's
  empty-scalar case); typed accessors don't re-decide it.

All parsing is whitespace-trimmed defensively even though libfyaml's
scalar decoding should already hand back trimmed content for plain
scalars.

## Where it lives

Add directly to `Libfyaml.Nodes` (`src/libfyaml-nodes.ads/.adb`) rather
than a new child package. The binding is still small enough that one
`Node` type with predicates + navigation + typed extraction together is
easier to discover than spreading it across `Libfyaml.Nodes.Scalars` or
similar. Revisit if the file grows unwieldy.

## Proposed API

New exceptions in `Libfyaml` (`src/libfyaml.ads`), alongside the
existing `Parse_Error`/`Emit_Error`:

```ada
Missing_Key : exception;
--  Raised by a *_Value(Map, Key) accessor when Key is required and
--  Map has no such key. Carries the key name and, where available,
--  identifying context (e.g. a nearby "name" field) in the message.

Data_Error : exception;
--  Raised when a scalar is present but cannot be resolved as the
--  requested type (e.g. Integer_Value on a node holding "banana").
--  Carries the offending text and target type in the message.
```

Per-node conversions (operate on a `Node` already known to be the
right one — e.g. via `Value`/`By_Path`):

```ada
function Integer_Value        (N : Node) return Integer;
function Long_Integer_Value   (N : Node) return Long_Integer;
function Long_Long_Integer_Value (N : Node) return Long_Long_Integer;
function Float_Value          (N : Node) return Float;
function Long_Float_Value     (N : Node) return Long_Float;
function Boolean_Value        (N : Node) return Boolean;

--  Non-raising predicates, for variant/shape dispatch — e.g. deciding
--  whether a list element is a plain string or a structured
--  [name, count]-style pair before committing to a conversion.
function Is_Integer (N : Node) return Boolean;
function Is_Float   (N : Node) return Boolean;
function Is_Boolean (N : Node) return Boolean;
```

Mapping + key convenience forms — collapses `Value (Map, Key)` +
`*_Value (N)` into one call, and folds in required/optional semantics
directly (rather than leaving every consumer to hand-roll its own
`Must_Integer`/`May_Integer` pair on top of `Value`/`*_Value`):

```ada
--  Required: raises Missing_Key if absent, Data_Error if malformed.
function Integer_Value (Map : Node; Key : String) return Integer;
function Long_Integer_Value (Map : Node; Key : String) return Long_Integer;
function Long_Long_Integer_Value (Map : Node; Key : String) return Long_Long_Integer;
function Float_Value   (Map : Node; Key : String) return Float;
function Long_Float_Value (Map : Node; Key : String) return Long_Float;
function Boolean_Value (Map : Node; Key : String) return Boolean;
function String_Value  (Map : Node; Key : String) return String;  -- Missing_Key only

--  Optional: Default returned if Key is absent; still raises
--  Data_Error if Key is present but malformed (absence and
--  malformed-ness are different failure modes and should stay
--  distinguishable).
function Integer_Value (Map : Node; Key : String; Default : Integer) return Integer;
function Long_Integer_Value
  (Map : Node; Key : String; Default : Long_Integer) return Long_Integer;
function Long_Long_Integer_Value
  (Map : Node; Key : String; Default : Long_Long_Integer) return Long_Long_Integer;
function Float_Value   (Map : Node; Key : String; Default : Float) return Float;
function Long_Float_Value
  (Map : Node; Key : String; Default : Long_Float) return Long_Float;
function Boolean_Value (Map : Node; Key : String; Default : Boolean) return Boolean;
function String_Value  (Map : Node; Key : String; Default : String) return String;
```

`String_Value` is included for symmetry even though `Scalar_Value`
already exists — it's the same "required-or-defaulted mapping lookup"
shape as the numeric/boolean accessors, so a caller doing
`Map.Integer_Value("points")` right next to
`Map.String_Value("name")` shouldn't have to special-case the string
case through a different calling convention (`Map.Value("name").
Scalar_Value` vs. everything else).

A `Required (Map : Node; Key : String) return Node` helper (raises
`Missing_Key`, otherwise identical to `Value`) is worth adding too, for
callers who want the `Node` itself rather than an immediately-converted
scalar — e.g. to check `Is_Sequence` before iterating a required list
field.

## Example

```ada
Points : constant Integer := Attribute.Integer_Value ("points");   -- required
Level  : constant String  := Attribute.String_Value ("level", ""); -- optional
Mecha  : constant Boolean := Entity.Has_Key ("mecha");             -- presence
   --  check only; Has_Key is unchanged by this plan. Whether "key present"
   --  or "key present and true" is the right test for a given boolean-ish
   --  field is a call-site decision, not something this layer should
   --  paper over by guessing.
```

## Timestamps

Not part of YAML 1.2 core schema, and not implemented by libfyaml at
any layer (see Design goals above) — this is new Ada-side parsing over
`Scalar_Value`'s text, never delegated to the C library.

**Format accepted:** the YAML 1.1 `!!timestamp` grammar, which is the
de facto convention most real-world YAML implements regardless of which
spec version they otherwise follow (PyYAML, SnakeYAML, Chicken's `yaml`
egg, etc. all implement it this way):

- date-only: `YYYY-MM-DD`
- full: `YYYY-MM-DD` then either `T` or one-or-more spaces, then
  `HH:MM:SS`, then an optional `.` and fractional-second digits of any
  length, then an optional zone: nothing (implies UTC), `Z`, or
  `±HH:MM`/`±HH` with optional surrounding whitespace before it (the
  1.1 grammar is deliberately lax here).

**API:**

```ada
function Timestamp_Value (N : Node) return Ada.Calendar.Time;
function Is_Timestamp    (N : Node) return Boolean;   -- shape check, non-raising

function Timestamp_Value (Map : Node; Key : String) return Ada.Calendar.Time;
function Timestamp_Value
  (Map : Node; Key : String; Default : Ada.Calendar.Time) return Ada.Calendar.Time;
```

Same `Missing_Key`/`Data_Error` conventions as the numeric accessors.
Needs `Ada.Calendar`, `Ada.Calendar.Formatting`, and
`Ada.Calendar.Time_Zones` — all standard, no new external dependency.

**Implementation approach:** `Ada.Calendar.Formatting.Value` expects one
fixed format and won't handle the full grammar above (arbitrary
fractional-second precision, `T`-or-space separator, optional zone,
date-only form), so this needs a small hand-written scanner that pulls
out year/month/day/hour/minute/second/sub-second/zone-offset fields from
the scalar text, then calls `Ada.Calendar.Formatting.Time_Of` — which
does accept a `Time_Zone` parameter (an offset in minutes) — to fold the
parsed zone offset into the correct absolute `Time` value.

**Design decision to flag explicitly:** `Ada.Calendar.Time` has no
memory of the original UTC offset — a timestamp parsed as `... +05:00`
and one parsed as `... Z` that name the same instant become
indistinguishable `Time` values. That's a real information loss versus
the source YAML, accepted here as the simple v1 behavior (matches what
most timestamp-consuming code wants — a comparable/absolute instant, not
the writer's local clock). Preserving the original offset would need a
small dedicated record type instead of bare `Ada.Calendar.Time`; noted
as an open question below rather than built now.

## Anchors, aliases, merge keys, and explicit tags

**[done]** Implemented as described below, with two differences from
the original plan:

- **Only `fy_document_resolve`, `fy_node_get_style`, and
  `fy_node_get_tag` got bound in `Libfyaml.Thin`**, not the full list
  originally proposed (`fy_node_get_anchor`, `fy_anchor_get_text`,
  `fy_anchor_node`, `fy_document_lookup_anchor`(+variants),
  `fy_node_resolve_alias`, `fy_node_dereference`). Those three are
  exactly what `Is_Alias`/`Tag`/`Resolve` below need; the rest would
  support querying an anchor's *name* or dereferencing one alias at a
  time without a whole-document `Resolve`, but nothing in the thick
  API calls for that yet -- `Libfyaml.Thin`'s own header comment is
  explicit that it mirrors "the core entry points actually bound",
  not the full surface speculatively. Still open if a concrete need
  shows up.
- **`Resolve_Anchors` defaults to `True`**, deciding the open question
  originally left below: no released consumers to break, and a
  YAML-parsing library silently mis-decoding anchored input by
  default is the worse surprise for a new caller.

Covered by `test/test_anchors.adb`: both parse-time resolution
(default `True`, and `False` followed by an explicit `Resolve`),
`Is_Alias`/`Tag` on the raw unresolved tree, and `Resolve_Error` on a
genuine failure (a merge-key reference loop, `test/anchors_cycle.yaml`).

**One thing found while implementing this, not by inspection:**
resolving a document with a self-referencing merge key (a genuine
reference loop, not just a deeply-nested one) leaks a small, fixed
amount of memory -- confirmed live with valgrind -- entirely inside
libfyaml's own ref-loop-detection diagnostic path
(`fy_document_resolve` -> `fy_check_ref_loop` -> its
`fy_document_diag_report` call), against the libfyaml build linked
here (package-labeled `0.8-9.fc44`, already exposing the 1.0-beta1
API this binding targets). Parsing the same fixture without calling
`Resolve`, and resolving every other fixture, are both confirmed
leak-free -- only this exact failure path inside libfyaml itself
leaks, so there is nothing to fix on the Ada side; noted here (and at
the point of the test that triggers it) so a future valgrind run
isn't mistaken for a new regression in this binding.

**Current gap, precisely (as it stood before the fix above):**
`Libfyaml.Documents.Parse_String`/
`Parse_File` never set `FYPCF_RESOLVE_DOCUMENT`, and `alibfyaml` doesn't
bind `fy_document_resolve()` at all. Concretely, this means an anchored
node (`&foo ...`) parses and queries fine at its point of definition,
but a node referencing it (`*foo`) sits in the tree as a node whose
`fy_node_get_type` is `FYNT_SCALAR` and whose *style* is `FYNS_ALIAS`
(confirmed in the libfyaml source: `fy_node_is_alias` is
`fy_node_get_type(fyn) == FYNT_SCALAR && fy_node_get_style(fyn) ==
FYNS_ALIAS` — another `static inline` convenience wrapper, not an
exported symbol, exactly the same situation `Is_Scalar`/`Is_Sequence`/
`Is_Mapping` were already in and were reimplemented in Ada for). Calling
today's `Scalar_Value` on such a node does **not** give the referenced
content — it gives whatever the alias token's own text is, silently.
Same story for `<<: *foo` merge keys: unresolved, the mapping just has a
literal `"<<"` key whose value is an unresolved alias, not the merged-in
pairs.

**This is worth prioritizing over "missing feature":** it's a
silent-wrong-output bug class today, not a loud missing-feature error —
any current `alibfyaml` consumer whose YAML happens to use anchors,
aliases, or merge keys is already getting incorrect data without any
indication of it.

**Fix, two parts:**

1. **Bind the missing pieces in `Libfyaml.Thin`** (all confirmed
   `FY_EXPORT` real symbols, not inline wrappers): `fy_document_resolve`,
   `fy_node_get_style`, `fy_node_get_anchor`, `fy_anchor_get_text`,
   `fy_anchor_node`, `fy_document_lookup_anchor` (and
   `_by_token`/`_by_node` variants), `fy_node_resolve_alias`,
   `fy_node_dereference`, and `fy_node_get_tag` (raw explicit-tag text,
   e.g. `tag:yaml.org,2002:str` or a custom `!mytag` — also the way to
   detect an explicit `!!timestamp` tag distinct from a plain scalar
   that merely looks date-shaped, cross-referencing the Timestamps
   section above).

2. **Expose in the thick API:**
   - `Libfyaml.Nodes.Is_Alias (N : Node) return Boolean` — reimplemented
     in Ada from `fy_node_get_type`/`fy_node_get_style`, same treatment
     as `Is_Scalar`/`Is_Sequence`/`Is_Mapping`.
   - `Libfyaml.Nodes.Tag (N : Node) return String` — wraps
     `fy_node_get_tag`; `""` if the node has no explicit tag.
   - `Libfyaml.Documents.Resolve (Doc : in out Document)` — wraps
     `fy_document_resolve`; raises a new `Libfyaml.Resolve_Error`
     exception (the C call returns 0/-1) on failure. Needed for
     documents built programmatically (`Create_*`/`Set_Root`) rather
     than parsed.
   - A `Resolve_Anchors : Boolean := False` parameter added to
     `Parse_String`/`Parse_File`, setting `FYPCF_RESOLVE_DOCUMENT` in
     `Fy_Parse_Cfg.Flags` when `True` (one code path, rather than
     parse-then-separately-call-`Resolve`).

   The `False` default is a placeholder, not a settled decision — see
   open questions.

## Is_Null_Value on an unresolved alias node (fixed)

**[done]** Found via the sibling `slibfyaml` binding (Chicken Scheme,
`~/Repos/Scheme/Chicken/5/slibfyaml`), not by anything in this
project's own test suite.** `Is_Null_Value` (`src/libfyaml-nodes.adb`)
calls `Thin.fy_node_is_null` unconditionally:

```ada
function Is_Null_Value (N : Node) return Boolean is
  (Boolean (Thin.fy_node_is_null (N.Handle))
   or else (Is_Scalar (N) and then Is_Null_Text (Trimmed (Scalar_Value (N)))));
```

`slibfyaml`'s Phase 7 work (its own `PLAN.md`) root-caused, with
`valgrind --track-origins=yes` after a test intermittently misbehaved,
that calling `fy_node_is_null` on an **unresolved alias node** (one
drawn from the streaming parser, i.e. `Document_Stream`/`Open_String`/
`Open_File`, before `Resolve`/`Resolve_Anchors => True` has run) reads
an uninitialized field entirely inside libfyaml itself
(`fy_token_alloc_rl` via the scan/fetch/parse call chain in
`fy-parse.c`) — the node intermittently, non-deterministically reads
back as null when it isn't. Confirmed by `slibfyaml` to be scoped to
the streaming parser specifically: `fy_document_build_from_string`/
`_file`'s one-shot path (what `Parse_String`/`Parse_File` use) does
not allocate through the same code and never reproduces it; only
`Document_Stream` (`fy_parse_load_document`) can trigger it.

**Not confirmed to have actually misfired in this codebase** — no test
here called `Is_Null_Value` on an unresolved alias node before this
fix, so libfyaml's uninitialized-field read was never exercised here —
but the exposure was structurally identical: `Is_Null_Value` had the
same shape here as `node-null-value?` did in `slibfyaml` before its
fix, and `Document_Stream` gives `alibfyaml` the same unresolved-alias
starting state `slibfyaml`'s streaming parser does.

**Fix applied, ported directly from `slibfyaml`'s own fix:**
`Is_Null_Value` now short-circuits to `False` for any `Is_Alias (N)`
node, skipping `fy_node_is_null` (and the null-text-spelling check)
entirely — justified independently of the libfyaml-internal bug, too:
an unresolved alias's own scalar text is a reference name (the anchor
being pointed to), not real content, so neither check is a meaningful
question to ask of it pre-resolution. Covered by a new check in
`test/test_anchors.adb` on the existing unresolved alias node (`Same`,
in the `Resolve_Anchors => False` block, before the explicit
`Resolve`) — confirmed leak-free under valgrind, along with the full
existing test suite re-run with no regressions.

## Multi-document YAML streams

**[done]** Implemented as `Libfyaml.Documents.Streams.Document_Stream`
(`src/libfyaml-documents-streams.ads/.adb`, a *child* package of
`Libfyaml.Documents` — see "Design" below for why it has to be a child
rather than living directly in `Libfyaml.Documents` alongside
`Document`). Covered by `test/test_streams.adb`: reads all three
documents from a file and from a string in order, confirms
`Parse_File` still only ever sees the first document of the same file,
confirms `Has_Next` stays `False` once exhausted, and confirms a
malformed second document raises `Libfyaml.Parse_Error` rather than
looking like a clean end of stream. Also re-verified directly against
the real two-document composite file from the `besm2_fmt` session that
first found this gap — both entities now read correctly.

**A second real lifetime bug found implementing this, not by
inspection:** `Open_File`'s first version freed its filename buffer
right after `fy_parser_set_input_file` returned success, reasoning (by
analogy with `fy_document_build_from_file`) that the filename wasn't
retained beyond the call. Wrong — confirmed by the doc comment, which
this reasoning had glossed over: "while the parser is in use the
file[name] must be available." The file is evidently opened lazily,
per `fy_parse_load_document` call, using the stored filename pointer —
so freeing it right after setup was a use-after-free that only showed
up as a mysterious `"[ERR]: failed to open <garbage>"` from libfyaml
partway through iterating the stream, with the garbage differing
between runs (freed/reused stack memory). A pure-C reproduction using
a string *literal* filename didn't reproduce it at all (literals are
never freed), which is exactly why it needed tracing rather than just
"looks fine in C". Fixed the same way `Parse_String`'s buffer bug was:
the stream (not any one document) owns and frees the buffer, now for
*both* `Open_String`'s text and `Open_File`'s filename.

**The gap, precisely (as found, before the fix above):**
`Libfyaml.Documents.Parse_String`/
`Parse_File` wrap `fy_document_build_from_string`/`_file`, which build
and return exactly *one* `fy_document`. Given a file containing more
than one `---`-separated YAML document, only the first is parsed;
later documents are silently dropped — no error, no exception, no
truncation warning. Found by hand while exercising `besm2_fmt` on a
two-document composite test file: the second entity just never
appeared in the output, with a clean exit status.

**Confirmed this is `alibfyaml`'s gap, not libfyaml's:** running
libfyaml's own `fy-tool` (its bundled dump/re-emit CLI) against the
identical multi-document file correctly parses and re-emits *both*
documents, each with its own `---`. `fy-tool` reaches a different,
lower-level libfyaml API for this — repeated `fy_parse_load_document`
calls against an `fy_parser` advance through a stream one document at
a time, returning `NULL` once exhausted — which `alibfyaml` doesn't
bind at all; only the single-document convenience functions are
bound (see `src/libfyaml-thin.ads`).

**Design, confirmed against libfyaml's own source (not just the
headers):** libfyaml itself splits this the same way `Document`/
`Document_Stream` now do —
`fy_document_build_from_string`/`_file` build exactly one document;
the streaming layer is `fy_parser_create` →
`fy_parser_set_string`/`fy_parser_set_input_file` → repeated
`fy_parse_load_document(fyp)` calls, `NULL` once exhausted →
`fy_parser_destroy`. Confirmed this is genuinely the intended idiom,
not just what `fy-tool` happens to do: libfyaml's own internals
(`src/lib/fy-parse.c`) use `while ((fyd = fy_parse_load_document(fyp))
!= NULL) { ... }` themselves.

**`Libfyaml.Thin` additions** (all confirmed real `FY_EXPORT` symbols):

```ada
type Fy_Parser is new System.Address;
Null_Fy_Parser : constant Fy_Parser := Fy_Parser (System.Null_Address);

function fy_parser_create (Cfg : access constant Fy_Parse_Cfg) return Fy_Parser;
procedure fy_parser_destroy (Fyp : Fy_Parser);
function fy_parser_set_string (Fyp : Fy_Parser; Str : CS.chars_ptr; Len : C.size_t) return C.int;
function fy_parser_set_input_file (Fyp : Fy_Parser; File : CS.chars_ptr) return C.int;
function fy_parse_load_document (Fyp : Fy_Parser) return Fy_Document;
```

**`Libfyaml.Documents.Streams` (a child package, not the same package
as `Document`) — what actually got built:**

```ada
type Document_Stream is tagged limited private;

function Open_String (Text : String) return Document_Stream;
function Open_File   (Path : String) return Document_Stream;

function Has_Next (Stream : in out Document_Stream) return Boolean;
function Next (Stream : in out Document_Stream) return Document
  with Pre => Has_Next (Stream);
```

This differs from the original sketch in this plan in two ways, both
forced by things the compiler caught (not just style preferences):

- **A `Has_Next`/`Next` function pair, not an out-parameter procedure.**
  The original idea — `procedure Next (Stream : in out Document_Stream;
  Doc : out Document; Has_Document : out Boolean)` — doesn't compile:
  `Document` is limited, and limited types have no assignment
  operation at all, including inside a procedure body assigning to an
  `out` parameter (`Doc := ...;` is illegal there just like anywhere
  else) — only object *initialization* (a function's `return`,
  build-in-place) is allowed for limited types. `Has_Next`/`Next` as
  functions returning `Document` via ordinary `return` sidesteps this
  entirely, at the cost of needing one-ahead read-ahead buffering
  inside `Document_Stream` (a `Pending`/`Peeked` pair) since libfyaml's
  own API has no side-effect-free way to "peek" the next document.

- **A child package, not part of `Libfyaml.Documents` itself.** `Next`
  needs both `Document_Stream` (parameter) and `Document` (result) in
  its profile, and both are tagged types. Ada disallows a subprogram
  from being a dispatching primitive of two different tagged types
  declared in the same immediate scope — declaring `Document_Stream`
  directly alongside `Document` hit exactly that restriction
  ("operation can be dispatching in only one type"). Making
  `Document_Stream` live in a *child* package instead resolves it:
  `Document`, declared in the parent, isn't in this package's own
  scope, so `Next` here is only ever a primitive of `Document_Stream`
  — and a child package still has full visibility into its parent's
  private part, so `Next` can construct a `Document` directly, exactly
  the way `Libfyaml.Documents`' own `Parse_String`/`Parse_File` do
  (their shared `Collected_Errors` helper moved from body-private to
  the parent spec's private part so the child could reuse it too,
  rather than duplicating that formatting logic).

**`Document` itself does not change.** A `Document` produced by `Next`
is the *same type*, wrapping the `Fy_Document` handle
`fy_parse_load_document` returns, finalized by the existing `Finalize`
that already calls `fy_document_destroy`. Checked whether
stream-produced documents actually need the paired
`fy_parse_document_destroy(fyp, fyd)` instead: its `fyp` parameter is
marked `FY_UNUSED` in libfyaml's own implementation
(`src/lib/fy-doc.c`), so plain `fy_document_destroy` is confirmed
equivalent — no destroy-path branching needed. `Document_Stream` is
purely an alternate constructor path; every existing `Document` method
(`Root`, `To_YAML`, ...) works unchanged on a stream-yielded one.

Two details needed to be right, both because of things this session
already got wrong once on the single-document path — and one of them
(the second) was gotten wrong *again* here too, the same class of bug
in a new spot:

1. **Buffer lifetime — for `Open_String`'s text *and*, it turned out,
   `Open_File`'s filename.** `fy_parser_set_string`'s doc comment
   carries the same warning `Parse_String`'s fix (above) was for:
   "while the parser is active the string must not go out of scope."
   Assumed by analogy that `Open_File`'s filename was safe to free
   right after `fy_parser_set_input_file` returned success (like
   `Parse_File` does) — wrong; see the bug writeup above the "gap"
   section. Both buffers are owned and freed by `Document_Stream`
   itself (an `Owned_Buffer` field, same shape as `Document`'s),
   freed in `Finalize` *after* `fy_parser_destroy`, since either one
   must outlive *every* document drawn from the stream, not just one.

2. **A mid-stream parse error must not look like clean end-of-stream.**
   `fy_parse_load_document` returning `NULL` is ambiguous on its own —
   "no more documents" and "document 2 was malformed" look identical.
   A shared private `Fetch` helper (used by both `Has_Next`'s
   read-ahead and `Next`'s own direct fetch, so the two can't drift out
   of sync on this) checks `fy_diag_got_error` whenever it sees `NULL`:
   a collected error means raise `Libfyaml.Parse_Error` with the
   collected diagnostic text (same as `Parse_String`/`Parse_File`
   today); only a clean `NULL` with nothing collected means genuine
   exhaustion.

**Non-breaking, confirmed by construction:** `Parse_String`/
`Parse_File` are untouched — same signature, same "exactly one
document" meaning. `Document_Stream` is purely additive; existing
callers who know their input is single-document see no change at all.

## Parse_Common double-free on every parse failure (fixed)

**[done]** Found live while investigating source-location access
(unrelated work), not by inspection: `Libfyaml.Documents.Parse_File`/
`Parse_String` crashed the process on genuinely malformed input,
instead of raising `Libfyaml.Parse_Error`.

`Parse_Common`'s `Handle = Null_Fy_Document` branch destroyed `Diag`
and then raised `Parse_Error`. Its own "defense in depth"
`exception when others => Thin.fy_diag_destroy (Diag); raise;`
handler then caught that same raise and destroyed `Diag` a *second*
time — glibc's `free()` detects the corruption and aborts the
process (confirmed live: `double free detected in tcache 2`) before
`Parse_Error` ever reaches the caller. This hit every single call to
`Parse_File`/`Parse_String` on malformed input, unconditionally.

**Why no existing test caught this:** `test_streams.adb`'s
`Parse_Error` checks go through `Libfyaml.Documents.Streams`, a
different code path with a different (and, confirmed separately,
correct) `Diag` lifecycle — one `Diag` kept alive for a whole
stream, destroyed once in `Finalize`, never per-call.
`test_quickstart.adb`'s `Parse_Error` handler exists but is only ever
reached with valid input in practice. Nothing exercised
`Parse_File`/`Parse_String` actually failing to parse until this.

**Fix:** stop destroying `Diag` on the failure branch itself; let the
single `exception when others` handler be the *only* place `Diag` is
destroyed on any failure path (it already ran on every path via
`raise`/re-raise, so this removes the duplicate rather than adding a
new one). Covered by `test/test_parse_errors.adb`: both
`Parse_File` and `Parse_String` on malformed input, back-to-back
independent failures (confirming no per-call state carries over,
since `Parse_Common` creates and destroys a fresh `Diag` each call —
unlike `Document_Stream`), and successful parsing afterward. All
confirmed leak- and error-free under valgrind.

## Parse_Error message reformatted to gcc diagnostic style (fixed)

**[done]** `Collected_Errors` (the function behind every
`Parse_Error` message) used to emit `file:` then `Err.Line'Image`
directly — GNAT's `'Image` on a signed integer carries a leading
space for a non-negative value, so the actual text was
`"file: 3: 1: message"`, not `"file:3:1: message"`, and had no
severity keyword at all. Found while building two example programs
(`test/example_syntax_error.adb`, `test/example_value_error.adb`)
meant to demonstrate reporting an error in gcc's own
`file:line:column: error: message` format — the existing message
didn't actually match it.

Fixed by trimming each number's `'Image` and inserting `"error: "`
before the text. Hardcoding `"error"` rather than mapping
`Fy_Diag_Error.Err_Type` to a real severity word is deliberate:
`fy_diag_errors_iterate`'s own naming and doc comment ("iterates over
the errors collected") indicate every entry reaching this function is
already an error, not a mix of severities filtered down to one label.
No test asserted the old exact message text (only that it was
non-empty), so this is a pure formatting improvement, not a breaking
change to anything in this repo.

## Document_Stream buffer lifetime -- a Document could outlive its Stream (fixed)

**[done]** Found while writing the "which Node-returning accessors
hand back buffer-tied data" documentation this section itself
answers (000-todo.org's zero-copy-analysis item) -- not by
inspection, but by actually checking the one case that question
implied and no existing test covered: does a `Document` drawn from
`Document_Stream.Next` remain correctly readable after the
`Document_Stream` itself is destroyed?

**Confirmed live: no, for `Open_String`.** `Document_Stream`'s
`Owned_Buffer` (the parsed text) was solely owned by the stream,
freed unconditionally in the stream's own `Finalize` -- with no
regard for whether a `Document` drawn from it (via `Next`) was still
alive and still holding a zero-copy span directly into that same
buffer (`fy_parser_set_string`, like `fy_document_build_from_string`,
doesn't copy its input). Destroying the stream while such a Document
was still in use was a genuine use-after-free: no crash, just
silently wrong data -- an empty string in one run, coincidentally
correct-looking leftover bytes in another (same "confirmed live" bug
class as the `Insert_At`/`Parse_String`/`Open_File`-filename findings
earlier in this file). `Open_File`-based streams have no equivalent
hazard -- confirmed separately, live: each document's own content is
independently backed, not shared with the stream's (much smaller)
owned buffer, which is only ever the *filename*.

**Fix:** a small reference-counted handle, `Buffer_Ref` (declared in
`Libfyaml.Documents`'s private part, alongside `Collected_Errors`, for
the same reason -- so the child package can reuse it), wraps the
`chars_ptr` buffer. `Document.Owned_Buffer` and
`Document_Stream.Owned_Buffer` are both `Buffer_Ref` now (previously
a plain `chars_ptr` on each). `Adjust`/`Finalize` do the refcounting:
the underlying text is freed only once the *last* `Buffer_Ref`
referencing it is finalized, regardless of which owner -- the stream,
or any number of `Document`s drawn from it -- goes out of scope
first. `Document_Stream.Next` gives every `Document` it returns a
shared copy of the stream's own `Owned_Buffer` when the stream was
opened via `Open_String` (and none, as before, when opened via
`Open_File`, since no sharing is needed there).

This was a deliberate design choice among two real options put to
the project owner rather than decided silently: fix it with shared
ownership (chosen), or leave it as a documented hard constraint ("a
Document from Open_String must not outlive its Stream") enforced by
nothing but the doc comment. The constraint-only option was cheaper
but left a real, silent-wrong-data footgun with no loud failure mode
-- not an acceptable tradeoff once framed that way.

**Confirmed live with valgrind, both orderings:** a `Document` drawn
from `Open_String` and returned from a function (so the stream is
destroyed before the caller ever touches the Document) now reads
back correctly, 0 errors, all heap blocks freed. The far more common
ordering -- every Document finalized before its stream, as every
pre-existing `test_streams.adb` check already does -- remains
unaffected and still leak-free (459 allocs, 459 frees). Covered
permanently by a new check in `test_streams.adb`
(`Doc_Outliving_Its_Stream`).

**The answer to the original "general lifetime rule" question, now
that this is fixed:** there isn't a per-accessor rule a caller needs
to track. Every `Node`'s data is valid for exactly as long as its
`Document` is (the one rule already stated in `Libfyaml.Nodes`'s own
header comment) -- regardless of whether that `Document` came from
`Parse_String`, `Parse_File`, `Open_String`, or `Open_File`. That
uniformity is the deliverable, not a list of which specific
functions happen to be buffer-backed internally; see the extended
header comment in `src/libfyaml-nodes.ads` for the write-up aimed at
a binding consumer, not just this file's own development history.

**Still open, separately:** whether to expose the non-copying
`fy_node_create_scalar` alongside `Create_Scalar`. That is a genuinely
different question -- an *opt-in* zero-copy construction API, where
the caller (not this binding) would own the lifetime obligation --
not something this fix resolves or is blocked on.

## Zero-copy Create_Scalar -- decided not to pursue

**[decided]** Analyzed as the follow-up to the buffer-lifetime fix
above. `fy_node_create_scalar` (no-copy) vs. the already-bound
`fy_node_create_scalar_copy` differ only in whether libfyaml makes
its *own* internal copy of the scalar bytes. Either way, `Create_Scalar`
still has to turn the caller's Ada `String` into a heap C buffer first
(`CS.New_String`) -- Ada strings aren't null-terminated and are often
stack-allocated, so that first copy isn't avoidable from this binding.
The only thing a no-copy variant would save is libfyaml's *second*,
internal copy.

That saving is real but small, and every existing call site
(`test_mutate.adb`, `test_quickstart.adb`, `test_location.adb`) builds
a handful of scalars per document as one-off tree edits, not in a hot
loop -- there's no concrete workload here where one extra short-string
memcpy matters.

Against that: making the no-copy variant safe requires new
infrastructure `Document` doesn't have. The single `Owned_Buffer`
(`Buffer_Ref`) added above covers exactly one buffer (the parse
input); a zero-copy `Create_Scalar` would need `Document` to hold a
growable collection of `Buffer_Ref`s, one per zero-copy scalar ever
created on it, kept alive for the document's whole lifetime (no
libfyaml callback exists to signal "this node was removed/replaced,
its buffer can be freed now") -- real new complexity for a saving
nothing here needs yet.

Decided not to build it, following the same "no concrete need yet"
reasoning as the deliberately-not-built items under source-location
in `000-todo.org`, and the YAML-1.1-types cancellation. `Create_Scalar`
stays copy-only. Revisit only if a real caller shows up with a
scalar-construction workload where the extra copy is measurably
costly -- at which point the growable-`Buffer_Ref`-list design above
is the starting point, not open design space.

## Reading from an Ada Text_IO.File_Type -- Libfyaml.Documents.Text_IO

**[done]** Answers 000-todo.org's remaining open item: can alibfyaml
read from an already-open `Ada.Text_IO.File_Type`, including
`Current_Input`/`Standard_Input`, and how does that interact with
libfyaml's zero-copy handling?

**New child package**, not an overload in the parent: `Libfyaml.
Documents.Text_IO.Parse (File : Ada.Text_IO.File_Type; Resolve_Anchors
: Boolean := True) return Document`. Kept separate from `Parse_String`/
`Parse_File` because it depends on `Ada.Text_IO.C_Streams` (GNAT-
specific, obtains the C `FILE *` underneath an open `File_Type`) --
the same reasoning that already keeps multi-document streaming in its
own child package (`Libfyaml.Documents.Streams`) rather than the
parent: a consumer who doesn't need this input source, or who cares
about compiler portability, never pays for the dependency.

**Wired to `fy_document_build_from_fp`** (confirmed present in the
actually-linked library via `nm -D`, same discipline as the rest of
this file). Checked against libfyaml's own source (`fy-input.c`), not
assumed from its header comments:

- A `FILE*`-backed input (`fyit_stream`) is read lazily via `fread()`
  into a buffer libfyaml allocates and owns itself -- neither
  `Parse_File`'s mmap of the whole file (`fyit_file`) nor
  `Parse_String`'s zero-copy span directly into the caller's own
  buffer. The returned `Document` therefore holds no reference into
  anything Ada-owned (`Owned_Buffer` is never set for it), and `File`
  need not outlive it.
- libfyaml does **not** `fclose` the `FILE*` for this input kind
  (confirmed: `fy_input_reset`'s `fyit_stream` case only frees its own
  internal read buffer) -- `File` stays open and is entirely the
  caller's to close, same as any other GNAT `File_Type`.

**A real caveat, found live rather than assumed, documented in
`Text_IO`'s own doc comment and in `test/test_text_io.adb`:** libfyaml
reads in whole internal chunks sized independently of document
boundaries. For any file smaller than one chunk -- most real files --
a single `Parse` call silently `fread()`s the *entire remaining file*
out from under `File`, not just the bytes of the first document,
leaving `File` at end-of-file even though only the first document was
actually parsed. Confirmed with a throwaway probe against
`test/streams.yaml` (three documents, ~76 bytes total): after parsing
just the first, `End_Of_File (File)` was already `True`. A second
`Parse` call on the same `File` does not raise or error -- it just
silently sees no more bytes, never reaching a second document. This
rules out repeated one-shot `Parse` calls as a way to stream multiple
documents out of a `File_Type`; that would need libfyaml's other,
persistent-parser API (`fy_parser_set_input_fp` + repeated
`fy_parse_load_document` on one parser -- the same shape
`Libfyaml.Documents.Streams.Open_File` already uses for paths).
Not implemented here, since the motivating question was about reading
a `File_Type` at all, not streaming multiple documents from one --
cheap to add the same way later if a real need shows up, following
the same "no concrete need yet" reasoning as the zero-copy
`Create_Scalar` decision above.

**Diagnostics:** `Text_IO.Parse` reuses `Collected_Errors`'
`File_Override` parameter (already threaded through `Parse_Common`
for `Parse_String`'s `"(string-in-memory)"` label) to report
`Ada.Text_IO.Name (File)` as the "file" in a `Parse_Error`'s
gcc-style message -- confirmed live that this gives a real path for
an ordinary opened file and `"*stdin"` (GNAT's own convention, not
this binding's) for `Standard_Input`/`Current_Input`, both genuinely
informative, unlike `fy_document_build_from_fp`'s own fallback (a bare
`"<stream-N>"` naming the file descriptor, since the convenience
function passes no name of its own) which this binding avoids by not
using it.

**Confirmed live under valgrind**, three ways: the file-based and
`Current_Input`/`Set_Input` cases in `test/test_text_io.adb`; a
throwaway probe piping real content through the shell into
`Standard_Input` (0 errors, all heap freed, deleted after confirming);
and the full pre-existing test suite re-run after the refactor below,
unaffected.

### Parse_Common shared with Text_IO.Parse -- and the bug that refactor exposed

Sharing `Parse_Common` (previously body-only, private to `Parse_String`/
`Parse_File`) with `Text_IO.Parse` required moving its declaration into
`Libfyaml.Documents`'s spec, alongside `Collected_Errors` (already
shared with `Streams` the same way). That immediately hit a real Ada
rule: `Parse_Common` originally returned `Document`, a tagged type: a
*new* private-part subprogram with a controlling result of one's own
package's tagged type is illegal unless it overrides an inherited
operation (RM 3.9.3(10)). Fixed by having `Parse_Common` return the raw
`Thin.Fy_Document` handle instead, with each caller (`Parse_String`,
`Parse_File`, `Text_IO.Parse`) wrapping it into a `Document` itself --
exactly what `Parse_File` already did before this change, so only
`Parse_String` (which also attaches an `Owned_Buffer`) needed any real
rework.

That rework introduced a second, unrelated bug, found only because
this project runs every touched test under valgrind before calling
anything done: the natural-looking way to store `Parse_Common`'s
result was `Handle : constant Thin.Fy_Document := Parse_Common (...);`
in `Parse_String`/`Parse_File`'s declarative part. Valgrind showed
`C_Text`/`C_Path` leaking on every parse failure -- a regression this
same file already fixed once before (the `Parse_Common` double-free
section above), now reintroduced in a different shape.

**Root cause, confirmed with a minimal standalone reproduction, not
just inferred from the leak:** a subprogram body's own `exception`
handler does *not* catch an exception raised while elaborating that
same body's declarative part -- only exceptions raised while executing
its statements. `Parse_Common` raising `Libfyaml.Parse_Error` while
initializing `Handle` therefore propagated straight past
`Parse_String`'s own `when others => CS.Free (C_Text); raise;`
handler to the caller, skipping the cleanup entirely, on every single
parse failure. This is a genuine, easy-to-miss Ada gotcha -- code that
reads as "obviously inside the body, so obviously covered by its
handler" is not.

**Fix:** declare `Handle : Thin.Fy_Document;` uninitialized, and assign
it via `Handle := Parse_Common (...);` as a statement in the `begin`
block instead, so the existing handler covers it. Confirmed live with
valgrind against the exact three failure sites this broke
(`test/test_parse_errors.adb`'s malformed-file and two malformed-string
cases): 0 errors, all heap freed, both before this bug (verified
against a clean checkout of the prior commit) and after the fix.
Documented in `AGENTS.md`'s conventions section so it isn't
rediscovered the same way by a future refactor.

## Node/Document liveness enforcement

**[done]** Closes the gap the "Open questions" entry above used to
describe: `Node`'s lifetime contract ("valid as long as its owning
`Document` hasn't been `Finalize`d") is now enforced at runtime, not
just documented. Ported from the equivalent design in the sibling
`slibfyaml` binding (Chicken Scheme,
`~/Repos/Scheme/Chicken/5/slibfyaml`), adapted for a host with
deterministic destruction but no garbage collector.

**Design:** a small reference-counted flag, `Owner_Liveness`
(`src/libfyaml-nodes.ads`, private part), shared between a `Document`
and every `Node` drawn from it -- mirroring `Libfyaml.Documents`' own
`Buffer_Ref`/`Buffer_Cell` shape exactly (a refcounted heap cell,
freed only once the last reference is gone), applied here to a shared
boolean instead of a shared buffer:

- `Document` gains an `Owner : Nodes.Owner_Liveness` component, set to
  a fresh `Nodes.New_Owner_Liveness` (a live flag, refcount one) by
  every constructor: `Parse_String`, `Parse_File`,
  `Document_Stream.Next`, `Text_IO.Parse`.
- `Document.Finalize` calls `Nodes.Mark_Dead (Doc.Owner)` *before*
  calling `Thin.fy_document_destroy` -- so any `Node` still holding a
  copy of `Doc.Owner` observes "dead" rather than a still-live flag
  alongside an about-to-be-freed handle, the same ordering discipline
  `slibfyaml`'s own `document-destroy!` uses ("sets the box's slot to
  `#f` before calling `fy_document_destroy`").
- `Node.Wrap` now takes an `Owner : Owner_Liveness` parameter alongside
  `Handle`, stored as a new `Owner` component on `Node`. Every call
  site that builds a `Node` from a raw handle now threads the right
  `Owner` through: `Libfyaml.Documents`' `Root`/`Create_Scalar`/
  `Create_Sequence`/`Create_Mapping` pass `Doc.Owner`; `Libfyaml.Nodes`'
  own internal navigation (`Item`, `Iterate` for both sequences and
  mappings, `Value`, `By_Path`) propagates the *same* `N.Owner`/
  `Map.Owner`/`Seq.Owner` the source `Node` already carries, since a
  node reached by navigating from an existing one belongs to the same
  `Document`.
- `Is_Valid` is redefined as `N.Handle /= Thin.Null_Fy_Node and then
  Is_Alive (N.Owner)` -- folded into the existing check rather than
  added as a separate precondition, per this section's own "Open
  questions" text weighing that option against a standalone helper.
  This means **zero signature changes to any public accessor**: every
  existing `Pre => Is_Valid (N)` site automatically gains the new
  check for free, and a `Node` used after its `Document` is gone now
  raises a clean `Ada.Assertions.Assertion_Error` (with `-gnata`
  enabled, as both `.gpr` files already do) instead of reading freed
  memory -- the same failure class as the `Insert_At`/`Parse_String`/
  `Document_Stream` bugs elsewhere in this file, now caught instead of
  hit.

**A real structural constraint found while implementing this, not
anticipated in the original open question:** `Owner_Liveness` cannot
derive from `Ada.Finalization.Controlled` directly. Doing so makes it
a tagged type, and `Wrap`'s profile (`Owner : Owner_Liveness` alongside
a `Node` result, `Node` itself also tagged) then hits RM 3.9.3(10) --
one subprogram cannot be a dispatching primitive of two different
tagged types declared in the same immediate scope -- the exact
restriction `Libfyaml.Documents.Streams`' own header comment already
describes hitting for `Document`/`Document_Stream.Next` (resolved
there with a child package). A child package was not an option here,
since `Node` and `Owner_Liveness` both belong in `Libfyaml.Nodes`
itself. Fixed by splitting the refcounting into an inner tagged type,
`Owner_Ref` (the actual `Controlled` derivative), wrapped inside a
plain untagged `Owner_Liveness` record (`type Owner_Liveness is record
Ref : Owner_Ref; end record;`) -- Ada finalizes/adjusts a controlled
component automatically even when the enclosing type is itself
untagged and not controlled (RM 7.6), so refcounting still works
exactly the same way, one level removed, with no tagged-type conflict.

**Two rejected alternatives, considered and dropped before settling on
refcounting, both because they'd break this project's leak-free-under-
valgrind discipline or reintroduce the exact bug class being fixed:**

1. **A deliberate small leak** -- heap-allocate the flag once per
   `Document` and never free it (the cell must outlive `Document`'s own
   storage, since a `Node` needs to read it after the `Document` object
   itself is gone). Rejected: this would leak one cell for the life of
   the program on *every* `Document` ever created, breaking "confirmed
   leak-free under valgrind" for every single existing test, not just
   the ones this feature is meant to cover.
2. **An unchecked pointer directly into the `Document` object's own
   storage** (e.g. `Doc.Live'Unchecked_Access`, a plain `Boolean`
   component, no separate heap cell). Rejected: `Document`'s own
   storage becomes invalid (stack reused, or freed if heap-allocated)
   at the exact same moment its destruction makes the liveness check
   necessary -- reading through such a pointer after that point is
   itself a new use-after-free, the same failure class this feature
   exists to close, just moved to a smaller piece of memory.

**Confirmed leak-free under valgrind**, including the specific
scenario this feature targets: a new `test/test_liveness.adb` (8
checks) exercises a `Node` remaining valid while its `Document` is
alive (both the root and one reached by `By_Path`), both becoming
`Is_Valid => False` after the `Document` goes out of scope, an
accessor call on such a `Node` raising `Ada.Assertions.Assertion_Error`
rather than reading freed memory, `Null_Node` remaining an ordinary
invalid node (not a special case of this feature), and two `Node`s
drawn from the same `Document` becoming invalid *together* (confirming
the flag is shared per-`Document`, not tracked per-`Node`). Also
re-ran the full existing test suite (all `test_*.adb` and
`example_*.adb`) under valgrind after this change: identical
leak/error status to before it in every case, including
`test_anchors`' one already-documented libfyaml-internal leak
(confirmed bit-for-bit identical against a stash of the pre-change
tree, not just assumed unaffected).

**Performance: measured, not assumed.** The refcounting cost this
design accepts (see "Rejected alternatives" above) is real and
non-trivial, not negligible next to the FFI call each accessor already
makes -- confirmed by `bench/` (see AGENTS.md's Benchmarking section),
comparing this commit against the immediately-preceding one (the
`Is_Null_Value` fix, before any of this section's changes) via two
isolated `git worktree` builds of the same benchmark source:

| Benchmark | What it stresses | Old mean | New mean | Overhead |
|---|---|---|---|---|
| `bench_wide` (200,000-entity single `Document`, every entity navigated via `Value`) | `Node` creation/navigation -- one `Wrap` (hence one `Owner_Liveness` copy) per accessed field | 0.879 s | 1.007 s | **+14.5%** |
| `bench_streams` (20,000 small separate `Document`s, one at a time) | `Document` creation/destruction -- one `New_Owner_Liveness` alloc + `Mark_Dead` per document | 0.056 s | 0.062 s | **+10.7%** |

(10 runs each; both benchmarks print a checksum alongside the timing,
confirmed bit-for-bit identical between old and new in every run --
this is a pure speed cost, not a behavior change.) Both land in the
same ~11-15% range, matching the design: every `Node`/`Document` copy
now touches a heap-allocated refcounted cell (an `Adjust`/`Finalize`
pair), on top of the FFI call itself. Not investigated further or
optimized -- no concrete workload has flagged this as a problem, and
correctness (closing a real, confirmed-elsewhere use-after-free class)
was judged worth a double-digit-percent constant-factor cost on
Node/Document-heavy workloads. Revisit with `bench/` if that judgment
call needs to be reopened, e.g. against a workload that turns out to
be far more Node/Document-churn-heavy than these synthetic fixtures.

## Testing plan

Extend `test/` with scalar-typed fixtures (either a new YAML file or
additions to the existing `test/config.yaml`) covering:

- valid int/float/bool in both required and optional-with-default forms
- a present-but-malformed value for each type (expect `Data_Error`)
- an absent key in required form (expect `Missing_Key`) and optional
  form (expect `Default` returned)
- hex/octal integer forms, boolean case variants, and a value in each
  of `Integer`/`Long_Integer`/`Long_Long_Integer`'s range but not the
  narrower type(s), to confirm the right accessor is actually required
  for it
- timestamps: date-only, `T`- and space-separated, fractional seconds,
  `Z`, `+HH:MM`/`-HH:MM` offsets, and a malformed case (expect
  `Data_Error`)
- a YAML fixture using an anchor + alias and a `<<:` merge key: verify
  the *unparsed* tree shows the alias node via `Is_Alias`/`Tag` as
  described above, then verify `Resolve`/`Resolve_Anchors => True`
  produces the merged/dereferenced content
- a new `test_scalars.adb` mirroring the existing `test_quickstart.adb`/
  `test_sequence.adb` pattern, added to `test/test.gpr`'s `Main` list
- a two-document `---`-separated YAML fixture, once multi-document
  stream support (see that section above) lands: confirm both
  documents are actually reachable, not just the first

## Open questions

- **`Fy_Parse_Cfg`/`Fy_Diag_Error` are hand-mirrored Ada records, an
  ABI-drift risk `slibfyaml` deliberately avoided.** `Libfyaml.Thin`
  (`src/libfyaml-thin.ads`) declares both as Ada records `with
  Convention => C`, pinning this binding to those two C structs' exact
  field order/padding as of the libfyaml version it was written
  against — nothing checks that assumption against whatever
  `libfyaml.h` is actually installed at build time. The sibling
  `slibfyaml` binding (Chicken Scheme,
  `~/Repos/Scheme/Chicken/5/slibfyaml`) hit the same C structs and
  deliberately chose not to mirror them: it defines small
  `foreign-lambda*` C-snippet accessors (e.g. `"C_return(cfg->flags);"`)
  instead, letting the C compiler compute the real field offset at
  build time against the actual installed header — a technique it
  borrowed from the existing `yaml` Chicken egg's own `yaml_event_t`
  handling. Ada's analogue would be small C shim functions (e.g.
  `unsigned fy_parse_cfg_get_flags(struct fy_parse_cfg *cfg) { return
  cfg->flags; }`, compiled and linked in, called via `pragma Import`)
  instead of the mirrored records — real extra build-system surface
  (a `.c` file to compile), not a drop-in change, so not applied here
  without weighing that cost. No confirmed incident of actual
  ABI drift against this project's own libfyaml build; flagged as a
  standing risk this binding carries and `slibfyaml` doesn't, not
  something broken today.
- **YAML 1.1 boolean spellings** (`yes`/`no`/`on`/`off`): out of v1
  scope per the core-schema-only design goal above, but flag in case a
  consumer's data actually uses them — would need an opt-in "legacy
  schema" mode rather than silently widening the default.
- **`.inf`/`.nan` float literals**: deferred; cheap to add later
  without breaking the API (same function signatures, wider accepted
  input).
- **Generic/enumeration support**: a generic `function Enum_Value
  (N : Node) return Some_Enum` (via `'Value` on trimmed text) would be
  a natural follow-on for YAML string-enum fields, but adds API surface
  with no concrete need driving it yet — deferred until one shows up.
- **Big integers beyond `Long_Long_Integer`**: not planned; no known
  need.
- **Timestamp UTC-offset preservation**: `Ada.Calendar.Time` drops the
  original zone offset (see Timestamps section). Add a
  `Timestamp_With_Offset` record type later if a concrete need for the
  original offset shows up; not built in v1.
- ~~**`Resolve_Anchors` default value**~~ Resolved: `True`. No released
  consumers to break, and a YAML *library* silently mis-decoding
  anchored input by default is the worse surprise for a new caller.
- ~~**Should `Resolve` failure be recoverable?**~~ Resolved:
  still-usable, not fatal. `Resolve` only ever calls
  `fy_document_resolve (Doc.Handle)` and raises on a nonzero status --
  it never touches or invalidates `Doc.Handle` itself, so `Doc` stays
  a normal, finalizable `Document` after a caught `Resolve_Error`
  (confirmed live: `test_anchors.adb`'s reference-loop case does
  exactly this, and valgrind shows no Ada-side issue from it, only the
  libfyaml-internal leak noted above). What *is* unknown -- because
  `fy_document_resolve`'s header doesn't document it -- is how much of
  the tree got resolved before the error; `Doc`'s *content* should be
  treated as unreliable after a caught `Resolve_Error` even though the
  `Document` object itself remains safe to use and destroy normally.
- ~~**Multi-document stream API shape**~~ Resolved: `Document_Stream`
  with an `out`-parameter `Next` (see the Multi-document YAML streams
  section above) — mirrors `fy_parse_load_document`'s own "call again,
  `NULL` means done" shape directly, and sidesteps needing new
  machinery for `Document`'s limited/controlled-ness.
- ~~**Node/Document liveness enforcement is documentation-only.**~~
  Resolved: implemented. See the dedicated "Node/Document liveness
  enforcement" section below for the design actually built.
- **`Missing_Key`/`Data_Error` carry only a bare message, not
  `Path`/`Location`.** Confirmed by reading `libfyaml-nodes.adb`'s
  actual `raise` statements: `Required` raises `Missing_Key with
  "missing required key ""<Key>"""`, and every typed accessor's
  `Data_Error` similarly carries just a `"not a valid <type>: ...""`
  string -- neither exception carries the offending `Map`'s `Path` or
  the scalar `Node`'s `Location`, even though the accessor raising it
  already holds exactly the `Node`/`Map` needed to compute either.
  Today a caller who wants that context fetches and combines it by
  hand, exactly as `test/example_missing_field.adb` demonstrates
  (`Path (Server)` alongside the caught `Missing_Key`'s own message).
  A sibling binding to the same C library for a garbage-collected host
  (`slibfyaml`, Chicken Scheme, `~/Repos/Scheme/Chicken/5/slibfyaml`)
  decided to attach this automatically instead: its `missing-key`/
  `data` conditions carry `'path` (and `'line`/`'column` when
  available) as structured fields, populated by the same internal
  helper every typed accessor already funnels through to raise, with
  the message text folding the path in too (`"missing required key
  \"host\" at /server"`) -- costing nothing extra at the raise site
  since the node is already in hand. Ada exceptions don't carry
  structured fields as directly as a CHICKEN condition object does
  (an Ada equivalent would mean either widening `Message` at the raise
  site to include `Path`/`Location` text inline, or defining dedicated
  exception occurrence types/`Exception_Information` accessors for
  `Missing_Key`/`Data_Error` -- the latter a real API-shape decision,
  not just a formatting tweak). Deferred rather than decided: flagged
  here as a possible future enhancement, not applied -- changing what
  an already-shipped exception carries needs its own consideration,
  not something to fold in incidentally alongside noting the idea.
- **Should `Parse_String`/`Parse_File` warn about extra documents?**
  Now that `Document_Stream` exists as the correct tool for
  multi-document input, should the single-document functions detect
  "there's more after this document" and raise/log rather than
  silently ignoring it (today's behavior, unchanged by adding
  `Document_Stream` alongside them)? Detecting this needs one more
  `fy_parse_load_document` call after the first to see if it returns
  non-`NULL` — cheap, but changes `Parse_String`/`Parse_File` from
  "parse one document" to "parse one document, but also read ahead" -
  a real behavior/performance tradeoff, not just an obvious safety
  win, so left as a follow-on decision rather than bundled into the
  `Document_Stream` implementation.

## Non-breaking

Purely additive to `Libfyaml.Nodes`, `Libfyaml.Documents`, and
`Libfyaml`: new functions, one new optional constructor parameter (with
a default, so existing call sites are unaffected regardless of what that
default ends up being), and three new exceptions (`Missing_Key`,
`Data_Error`, `Resolve_Error`). No signature changes to anything
existing.
