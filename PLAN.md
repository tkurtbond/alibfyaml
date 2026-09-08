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

**Current gap, precisely:** `Libfyaml.Documents.Parse_String`/
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

## Multi-document YAML streams

**Current gap, precisely:** `Libfyaml.Documents.Parse_String`/
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

**Fix direction (not designed in detail yet):** bind `fy_parser_create`/
`fy_parser_destroy`/`fy_parse_load_document`/`fy_parser_set_input_*`
(or whichever subset the single-document path doesn't already need) in
`Libfyaml.Thin`, and add something like a `Libfyaml.Documents.
Document_Stream` type (or an iterator/callback over `Parse_String`/
`Parse_File`) that yields each `Document` in turn, distinct from the
current "parse exactly one document" `Parse_String`/`Parse_File` — those
should probably keep their current single-document behavior/signature
for callers who know their input is a single document, rather than
changing what they mean.

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
- **`Resolve_Anchors` default value**: proposed `False` above to avoid a
  silent behavior change for any existing caller, but there's a real
  argument for defaulting to `True` instead — a YAML *library* silently
  mis-decoding anchored input by default is arguably the worse surprise
  for a new caller, and `alibfyaml` has no released consumers yet to
  break. Needs a decision before implementing, not just a placeholder.
- **Should `Resolve` failure be recoverable?** `fy_document_resolve`
  returns -1 on error (e.g. a merge-key cycle); need to decide whether
  `Libfyaml.Resolve_Error` leaves the `Document` in a still-usable
  (just-unresolved) state or whether failure should be treated as fatal
  to that `Document`, matching how `Parse_Error` behaves today.
- **Multi-document stream API shape**: the Multi-document YAML streams
  section above names a fix direction but not a settled design — an
  iterator type, a callback-based `Parse_All`, or something closer to
  `fy_parse_load_document`'s own "call again for the next one, `NULL`
  means done" shape are all plausible; needs a real design pass rather
  than picking one here. Also unresolved: should `Parse_String`/
  `Parse_File` at least start raising or logging when given input with
  more than one document, given today's silent truncation, even before
  a real multi-document API exists?

## Non-breaking

Purely additive to `Libfyaml.Nodes`, `Libfyaml.Documents`, and
`Libfyaml`: new functions, one new optional constructor parameter (with
a default, so existing call sites are unaffected regardless of what that
default ends up being), and three new exceptions (`Missing_Key`,
`Data_Error`, `Resolve_Error`). No signature changes to anything
existing.
