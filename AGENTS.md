# AGENTS.md

Ada binding to libfyaml's core parser/emitter/document API. See
README.md for what this binding covers/doesn't cover, and PLAN.md for
design history and open questions. This file is operational notes for
an agent working in this repo, not a design doc.

## Build

```sh
gprbuild -P libfyaml_ada.gpr -p -largs $(pkg-config --libs libfyaml)
cd test
gprbuild -P test.gpr -p -largs $(pkg-config --libs libfyaml)
```

Full clean rebuild: `gprclean -P libfyaml_ada.gpr -r` then the same in
`test/` with `test.gpr`, before the commands above.

**Before assuming you need to build libfyaml from source** (as
README's "Building" section walks through): check what's already
available. `pkg-config --modversion libfyaml` reporting an old-looking
version (e.g. `0.8`) does not necessarily mean the API is old --
confirm what symbols are actually present, e.g.:

```sh
nm -D $(pkg-config --variable=libdir libfyaml)/libfyaml.so | grep fy_document_build_from_string
```

On this project's Fedora dev environment, the system package labeled
`0.8-9.fc44` already exposes the 1.0-beta1 API this binding targets,
so the system `pkg-config --libs libfyaml` just works -- no local
libfyaml build needed. Don't assume this holds on every machine;
verify, don't guess, and fall back to README's from-source steps if
the symbols this binding needs aren't there.

## Test

Every `test_*.adb` in `test/` is its own `Main` in `test/test.gpr` and
its own standalone executable (not a single test-runner). Run them
individually after building:

```sh
cd test
./test_quickstart config.yaml   # only this one takes an argument
./test_sequence
./test_scalars
./test_navigate
./test_streams
./test_mutate
./test_anchors
```

Each prints `ok   - <label>` / `FAIL - <label>` per check and ends
with "All checks passed." or "<N> check(s) failed." -- grep for `FAIL`
or check the trailing line, not just exit status.

**Adding a new `test_*.adb` requires two other edits**, easy to miss:
add it to `for Main use (...)` in `test/test.gpr`, and add
`test/test_<name>` to `.gitignore` (the built executables are
untracked, listed individually by name -- there's no wildcard).

### Run under valgrind for anything touching ownership/lifetime

This is not optional polish here. Every real bug found in this
binding so far (the `Parse_String`/`Open_File` buffer-lifetime bugs,
the `Insert_At` use-after-free, both documented in PLAN.md and git
history) surfaced as a test that *passed* while quietly reading freed
or premature memory -- caught only by valgrind, never by the test's
own pass/fail logic. If you touch anything that creates, frees, or
hands a C-side lifetime obligation across the Ada/C boundary, run the
affected test(s) under:

```sh
valgrind --leak-check=full --show-leak-kinds=definite,indirect --error-exitcode=99 ./test_whatever
```

before considering the change done, not just at the end of a session.

**One confirmed non-issue, so it isn't re-diagnosed as a regression:**
`test_anchors`' merge-key reference-loop case leaks a small, fixed
amount of memory *inside libfyaml itself* (`fy_document_resolve`'s own
ref-loop-detection diagnostic path) -- see the comment at that test
case and the "Anchors, aliases, merge keys, and explicit tags" section
of PLAN.md. Every other test, and every other case in `test_anchors`,
is confirmed leak-free.

## Layout

- `src/libfyaml-thin.ads` -- low-level 1:1 `Interfaces.C` imports, no
  ownership/error-checking policy. **Binds only C functions the thick
  layer actually calls**, not the full libfyaml surface speculatively
  -- if you need a new C entry point, confirm it's a real `FY_EXPORT`
  symbol (not a header-only `static inline` wrapper, which can't be
  bound via `pragma Import`) before adding it here.
- `src/libfyaml.ads` -- the exception types (`Parse_Error`,
  `Emit_Error`, `Missing_Key`, `Data_Error`, `Resolve_Error`).
- `src/libfyaml-nodes.ads/.adb` -- `Node`: cheap, non-owning handle.
- `src/libfyaml-documents.ads/.adb` -- `Document`: RAII owner of a
  parsed/built tree.
- `src/libfyaml-documents-streams.ads/.adb` -- multi-document
  streaming, a child package (see its own header comment for why it
  has to be a child rather than living in `Libfyaml.Documents`).
- `test/` -- one standalone program per concern, see Test above.
- `PLAN.md` -- design history, confirmed findings, and open questions,
  organized by feature section (append to the relevant section rather
  than starting a new doc). `[done]` marks a finished section; a
  struck-through open-question bullet marks a resolved decision.
- `000-todo.org` -- the actual backlog.

## Conventions specific to this codebase

- **Doc comments explain *why*, and only claim what's been verified.**
  This codebase's comments are full of "confirmed live" / "confirmed
  the hard way" -- that's deliberate, not decoration. libfyaml's own
  header comments have been incomplete or misleading more than once
  (e.g. `fy_document_insert_at`'s "unref'ed... if the operation fails"
  reads as failure-only but the unref is unconditional; `Open_File`'s
  filename lifetime requirement wasn't obvious from the function used
  for analogy). **When a comment or implementation decision rests on
  how the C library actually behaves, verify it** -- write a small
  throwaway Ada program exercising the case, run it (under valgrind if
  lifetime/ownership is in question), then delete the scratch file --
  rather than asserting it from the header text or from a plausible
  guess. Then write the comment as a confirmed fact, not a
  paraphrase of the header.
- **`with Pre => Is_Valid (N)` / `-gnata`**: preconditions throughout
  `Libfyaml.Nodes` are load-bearing, not decorative -- both project
  `.gpr` files enable `-gnata` specifically so they're checked at
  runtime (see the comment in `libfyaml_ada.gpr`). Don't disable it or
  work around a precondition failure by loosening the contract without
  understanding why it's failing first.
- **Node/Document handles can be silently invalidated by libfyaml
  itself**, not just by this binding's own calls -- e.g.
  `Insert_At`'s `N` parameter is unconditionally unref'ed by libfyaml
  and nulled out here in response; `Resolve`'s failure path leaves
  `Doc` itself safe to use but its *content* unreliable (libfyaml
  doesn't document how much resolved before an error). When adding a
  new mutating operation, work out and document what happens to every
  `Node`/`Document` argument on both success and failure -- don't
  assume "success" means "safe to keep using as before."
