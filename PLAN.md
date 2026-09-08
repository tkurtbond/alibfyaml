# Typed scalar accessors for alibfyaml

## Motivation

libfyaml's core API — the layer `alibfyaml` binds — deliberately hands
back scalar content as text (`fy_node_get_scalar`/`Scalar_Value`), with
one exception: `fy_node_is_null` / `Is_Null_Value`, which *is* a real
core-layer predicate, so "is this the null scalar" is already resolved
by the C library. Everything else — is `"8"` an integer, is `"true"` a
boolean, is `"3.5"` a float — is left to the caller. Implicit typing of
scalars lives in libfyaml's *generics* layer (`fy_generic`), which
`alibfyaml` doesn't bind (its ergonomic constructors are C11
`_Generic`/variadic macros with no C-callable equivalent — see
`src/libfyaml.ads`).

This surfaced while planning `besm2_fmt`
(`~/Repos/Ada/RPG/besm2_fmt/PLAN.md`), a port of a Chicken Scheme tool
that relies on the `yaml` egg decoding scalars into native numbers/
booleans automatically. That plan originally put a `Yaml_Access` typed-
conversion layer *inside* `besm2_fmt`. On reflection this belongs in
`alibfyaml` instead: "give me this mapping value as an `Integer`" is a
generically useful binding feature, not something specific to one BESM
tool, and every future consumer of `alibfyaml` would otherwise
reinvent it.

## Design goals

- Implement YAML 1.2 **core schema** scalar resolution for the types
  that schema defines (null, bool, int, float), as plain Ada functions
  over `Node`/`Scalar_Value` — no change to the underlying C binding.
- Fold in the "required key" / "optional key with default" pattern
  that typed access needs anyway, so `besm2_fmt`'s planned
  `Must_Integer`/`May_Integer` etc. collapse into direct calls here.
- Keep failure modes distinct and explicit: a **missing** key is not
  the same problem as a **malformed** value, and callers need to tell
  them apart (an optional field defaults cleanly if absent, but should
  still raise if present-and-garbage).
- Non-breaking, additive change to the existing `Libfyaml.Nodes` API.

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
- **Integer**: decimal, with `0x`/`0o` accepted per core schema.
  Provide both `Integer` (32-bit-plus) and `Long_Long_Integer` (64-bit)
  accessors, since point/level values in something like BESM data are
  small but a general binding shouldn't cap at 32 bits.
- **Float**: decimal + exponent form. `.inf`/`-.inf`/`.nan` deferred to
  an open question (rare in practice; easy to add later without an API
  break).
- Null resolution already exists (`Is_Null_Value`); typed accessors
  don't re-decide it.

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
function Long_Long_Integer_Value (N : Node) return Long_Long_Integer;
function Float_Value          (N : Node) return Float;
function Long_Float_Value     (N : Node) return Long_Float;
function Boolean_Value        (N : Node) return Boolean;

--  Non-raising predicates, for variant/shape dispatch (as
--  besm2_fmt's format-customizers port needs: is this list element a
--  plain string or a [name, count] pair?).
function Is_Integer (N : Node) return Boolean;
function Is_Float   (N : Node) return Boolean;
function Is_Boolean (N : Node) return Boolean;
```

Mapping + key convenience forms — collapses `Value (Map, Key)` +
`*_Value (N)` into one call, and folds in required/optional semantics
directly (mirroring what `besm2_fmt`'s `Must_Integer`/`May_Integer`
were going to hand-roll):

```ada
--  Required: raises Missing_Key if absent, Data_Error if malformed.
function Integer_Value (Map : Node; Key : String) return Integer;
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

## Example (post-change `besm2_fmt` usage)

```ada
Points : constant Integer := Attribute.Integer_Value ("points");   -- required
Level  : constant String  := Attribute.String_Value ("level", ""); -- optional
Mecha  : constant Boolean := Entity.Has_Key ("mecha");             -- unchanged;
   --  presence-check semantics are a besm2_fmt-level decision (see that
   --  repo's PLAN.md open question), not something this layer should
   --  paper over by guessing what "mecha: false" should mean.
```

With this in `alibfyaml`, `besm2_fmt`'s planned `Yaml_Access` package
shrinks to just the BESM-specific field names/shapes (e.g. the
`format-customizers` enhancement/limiter variant dispatch), not a
general typed-conversion layer — that generic problem is solved once,
here.

## Testing plan

Extend `test/` with scalar-typed fixtures (either a new YAML file or
additions to the existing `test/config.yaml`) covering:

- valid int/float/bool in both required and optional-with-default forms
- a present-but-malformed value for each type (expect `Data_Error`)
- an absent key in required form (expect `Missing_Key`) and optional
  form (expect `Default` returned)
- hex/octal integer forms, boolean case variants
- a new `test_scalars.adb` mirroring the existing `test_quickstart.adb`/
  `test_sequence.adb` pattern, added to `test/test.gpr`'s `Main` list

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
  a natural follow-on for YAML string-enum fields, but isn't needed by
  `besm2_fmt` and adds API surface — deferred until a concrete need
  shows up.
- **Big integers beyond `Long_Long_Integer`**: not planned; no known
  need.

## Non-breaking

Purely additive to `Libfyaml.Nodes` and `Libfyaml`: new functions and
two new exceptions, no signature changes to anything existing.
