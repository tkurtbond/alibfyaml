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
* `test/` — `test_quickstart.adb` (an Ada port of `examples/quick-start.c`)
  and `test_sequence.adb`, both built and run against a local libfyaml
  build as part of developing this binding.

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
