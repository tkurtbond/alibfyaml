# alibfyaml

An Ada binding to [libfyaml](https://github.com/pantoniou/libfyaml)'s core
parser/emitter/document API — the layer used by libfyaml's own
`examples/quick-start.c` and `examples/basic-parsing.c`: parse YAML/JSON
into a document tree, navigate and mutate it, emit it back out.

This repository holds only the Ada binding; it does not vendor libfyaml
itself. You need a separate checkout of libfyaml (targeting the 1.0-beta1
API — see the note under Building) to build and link against.

## Scope

This binding covers document lifecycle, node predicates/navigation,
sequence/mapping access and construction, path lookup, emission, and
diagnostics collection — see `src/libfyaml-thin.ads` for the exact function
list.

It intentionally does **not** cover:

* **Generics** (`fy_generic`): libfyaml's Python-`dict`/`list`-like
  sum-type value model. Its ergonomic constructors (`fy_mapping(...)`,
  `fy_sequence(...)`, `fy_value(...)`) are C11 `_Generic`/variadic macros
  with no C-callable equivalent to bind — the same wall the Python binding
  (`python-libfyaml/`) hits, which it works around by dropping to the
  `fy_gb_*` builder functions underneath. A generics binding is future
  work, built the same way.
* **Reflection**: typed YAML &lt;-&gt; C struct serdes driven by libclang or
  packed metadata. Doesn't have an Ada-struct analogue to target.
* **scanf/printf-style variadic entry points** (`fy_document_scanf`,
  `fy_node_buildf`, ...): Ada cannot call C variadic functions generically
  either. Use the typed navigation API instead (`By_Path`, `Value`,
  `Scalar_Value`, ...).

## Layout

* `src/libfyaml-thin.ads` — low-level 1:1 `Interfaces.C` imports. No
  ownership or error-checking policy; a direct mirror of the C entry
  points actually bound.
* `src/libfyaml.ads` — `Parse_Error` / `Emit_Error` exceptions.
* `src/libfyaml-nodes.ads/.adb` — `Node`: a cheap, non-owning handle onto
  a tree node (predicates, scalar/sequence/mapping access, path lookup).
* `src/libfyaml-documents.ads/.adb` — `Document`: an RAII (controlled)
  owner of a parsed or freshly-built tree (parse, build, emit).
* `src/libfyaml-documents-streams.ads/.adb` — `Document_Stream`: reads
  multiple `---`-separated documents from one input in sequence (see
  below); a child package of `Libfyaml.Documents`.
* `test/` — built and run against a local libfyaml build as part of
  developing this binding: `test_quickstart.adb` (an Ada port of
  `examples/quick-start.c`), `test_sequence.adb`, `test_scalars.adb`
  (exhaustive coverage of the typed scalar accessors below),
  `test_navigate.adb` (a worked example of tree navigation, not a
  pass/fail test), and `test_streams.adb` (multi-document streaming,
  including a mid-stream parse error).

## Typed scalar accessors

libfyaml's core layer only hands back scalar content as text; it does
not resolve `"8"` to an integer or `"true"` to a boolean. `Libfyaml.Nodes`
resolves this on the Ada side: `Integer_Value`, `Long_Integer_Value`,
`Long_Long_Integer_Value`, `Float_Value`, `Long_Float_Value`,
`Boolean_Value`, and `String_Value`, each as a per-node accessor and as
`(Map, Key)` required (raising `Libfyaml.Missing_Key` if absent,
`Libfyaml.Data_Error` if present but malformed) and optional-with-default
forms. Resolution follows
[YAML 1.2's core schema](https://yaml.org/spec/1.2.2/#103-core-schema):
decimal/`0x`-hex/`0o`-octal integers, decimal-with-exponent floats, and
`true`/`True`/`TRUE`/`false`/`False`/`FALSE` booleans. See `PLAN.md` for
the full design and `src/libfyaml-nodes.ads` for exact signatures.

### Extensions beyond YAML 1.2 core schema

Two accepted integer forms are a deliberate, documented extension
beyond what YAML 1.2 core schema itself defines:

* **`0b` binary** (e.g. `0b1010`): not part of YAML 1.2 core schema at
  all — it's a YAML 1.1 form. libfyaml's own *generics* layer (which
  this binding doesn't cover — see Scope above) recognizes it too, but
  only under an explicit YAML 1.1 schema selection; this binding
  accepts it unconditionally, regardless of the rest of the document
  otherwise following 1.2 core schema.
* **`_` as a digit separator** (e.g. `1_000_000`, `0xFF_FF`, `1_234.5_6`):
  accepted in decimal/hex/octal/binary integers and in the integer,
  fractional, and exponent parts of floats. A single underscore is
  accepted only strictly between two digits — never leading, trailing,
  or doubled.

Everything else — booleans, plain decimal/`0x`/`0o` integers, plain
floats — follows YAML 1.2 core schema exactly, no extensions.

## Multi-document YAML streams

`Libfyaml.Documents.Parse_String`/`Parse_File` always parse exactly one
document — given input with more than one `---`-separated document, they
silently parse only the first. For input that may hold more than one
document, use `Libfyaml.Documents.Streams.Document_Stream` instead:

```ada
declare
   Stream : Libfyaml.Documents.Streams.Document_Stream :=
     Libfyaml.Documents.Streams.Open_File ("multi.yaml");
begin
   while Libfyaml.Documents.Streams.Has_Next (Stream) loop
      declare
         Doc : Libfyaml.Documents.Document :=
           Libfyaml.Documents.Streams.Next (Stream);
      begin
         --  use Doc.Root, etc., same as a Parse_File-produced Document
         null;
      end;
   end loop;
end;
```

`Open_String`/`Open_File` build on libfyaml's separate streaming-parser
API (`fy_parser_create` + repeated `fy_parse_load_document`) rather than
the single-document `fy_document_build_from_string`/`_file` that
`Parse_String`/`Parse_File` use. A malformed document partway through the
stream raises `Libfyaml.Parse_Error`, distinct from `Has_Next` returning
`False` at a clean end of stream. See `PLAN.md` for the full design,
including two lifetime bugs found and fixed while implementing this.

## Building

This is a pure Ada import layer — no C headers are compiled, so only the
**linker** needs to find `libfyaml.so`/`.a` (built from this repository;
system packages may be a much older ABI — see note below):

```sh
gprbuild -P libfyaml_ada.gpr -p \
  -largs $(pkg-config --libs libfyaml)
```

or point `LIBRARY_PATH`/`-largs -L<dir>` at wherever you installed a
matching libfyaml build. To build and run the tests against a local
build, from a checkout of libfyaml (adjust `LIBFYAML_SRC`):

```sh
LIBFYAML_SRC=~/path/to/libfyaml
cmake -S "$LIBFYAML_SRC" -B /tmp/fyaml-build \
  -DCMAKE_INSTALL_PREFIX=/tmp/fyaml-prefix \
  -DBUILD_TESTING=OFF -DENABLE_LIBCLANG=OFF -DENABLE_REFLECTION=OFF
cmake --build /tmp/fyaml-build -j"$(nproc)"
cmake --install /tmp/fyaml-build

gprbuild -P libfyaml_ada.gpr -p
cd test
gprbuild -P test.gpr -p -largs -L/tmp/fyaml-prefix/lib64
LD_LIBRARY_PATH=/tmp/fyaml-prefix/lib64 ./test_quickstart config.yaml
```

**Note:** a `pkg-config --modversion libfyaml` on a system with an older
packaged libfyaml (e.g. 0.8) will not have the 1.0-beta1 API this binding
targets. Build libfyaml from source as above, or make sure
`PKG_CONFIG_PATH`/`LIBRARY_PATH` point at a matching build ahead of any
system copy.

## Example

```ada
declare
   D : Libfyaml.Documents.Document := Libfyaml.Documents.Parse_File ("config.yaml");
   Server : constant Libfyaml.Nodes.Node := D.Root.By_Path ("/server");
begin
   Ada.Text_IO.Put_Line (Server.Value ("host").Scalar_Value);
   Ada.Text_IO.Put (D.To_YAML (Libfyaml.Documents.Emit_Sort_Keys));
exception
   when E : Libfyaml.Parse_Error =>
      Ada.Text_IO.Put_Line (Ada.Exceptions.Exception_Message (E));
end;
```
