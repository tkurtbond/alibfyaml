# Issues in libfyaml

Problems found in libfyaml itself, the C library under this binding,
rather than in the binding. They are recorded here instead of in
libfyaml's issue tracker, because we don't know whether that project
takes bug reports there. Each one is numbered and dated, says which
libfyaml version showed it, gives a repro in C against libfyaml
alone, and says whether it has been reported upstream.

The same file, with the same numbers, is kept in alibfyaml (Ada),
olibfyaml (Oberon-2, voc) and polibfyaml (Oberon-2, poc).

## 1. A fold after an escaped line break loses spaces

Found 2026-11-15, through besm2_cg_po (polibfyaml) while porting it
to the web. Seen with libfyaml 0.8 (Fedora 44's libfyaml-devel
0.8-9.fc44). Not reported upstream, and not yet tried with
libfyaml 1.0.0-rc2.

When the emitter writes in block mode (`FYECF_MODE_BLOCK`, width 80)
and a double-quoted scalar has an escape (here `\"`), the emitter folds
long lines with an escaped line break (`\` at the end of the line). If
the fold falls just before a run of spaces, those spaces go at the start
of the next line, after its indentation. YAML drops leading white space
after an escaped line break, so the spaces are lost when the output is
read back. To keep them, the emitter would have to write the first
one as `\ `. Without an escape, a double-quoted scalar isn't folded at
all. In the default mode the width is unlimited, so nothing folds.

Repro, `fold.c`:

```c
/* libfyaml: a double-quoted scalar with an escape and two spaces where
   the emitter folds it doesn't read back the same. */
#include <stdio.h>
#include <string.h>
#include <libfyaml.h>

static const char *value(struct fy_document *d, size_t *n) {
  return fy_node_get_scalar(
      fy_node_by_path(fy_document_root(d), "/k", FY_NT, FYNWF_DONT_FOLLOW), n);
}

int main(int argc, char **argv) {
  const char *in = argv[1];
  struct fy_document *a = fy_document_build_from_string(NULL, in, FY_NT);
  size_t na, nb;
  const char *va = value(a, &na);
  char *out = fy_emit_document_to_string(a, FYECF_MODE_BLOCK);
  printf("--- emitted:\n%s", out);
  struct fy_document *b = fy_document_build_from_string(NULL, out, FY_NT);
  const char *vb = value(b, &nb);
  printf("--- before: [%.*s]\n--- after:  [%.*s]\n", (int)na, va, (int)nb, vb);
  printf("same: %s\n", na == nb && memcmp(va, vb, na) == 0 ? "yes" : "no");
  return 0;
}
```

```sh
cc -o fold fold.c $(pkg-config --cflags --libs libfyaml)
./fold 'k: " \"q\" aaaaa words words words words words words words words words words  two  spaces x y"'
```

Output:

```
--- emitted:
k: " \"q\" aaaaa words words words words words words words words words words  two\
   spaces x y"
--- before: [ "q" aaaaa words words words words words words words words words words  two  spaces x y]
--- after:  [ "q" aaaaa words words words words words words words words words words  twospaces x y]
same: no
```

In the bindings, this is emitting with `emitModeBlock` (Oberon) or
`Emit_Mode_Block` (Ada). besm2_cg_po saves this way, so each
`besm2_calc_po --fill` of its own output loses more spaces:
`words  two` becomes `wordstwo`, and so on, until the text stops
changing.
besm2_cg_web, its web port, writes and reads the same bytes, lost
spaces included (its PLAN.md, "Findings").
