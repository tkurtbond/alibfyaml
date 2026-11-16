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

## 2. A failed resolve while streaming doesn't set `fy_diag_got_error`

Found 2026-11-15, through pobesm2_fmt2 (polibfyaml) while porting
besm2_cg_po to the web. Seen with libfyaml 0.8 (Fedora 44's
libfyaml-devel 0.8-9.fc44). Not reported upstream, and not yet tried
with libfyaml 1.0.0-rc2.

When a parser created with `FYPCF_RESOLVE_DOCUMENT` loads a document
with an alias that can't be resolved (an undefined alias, or a cyclic
reference), `fy_parse_load_document` returns NULL and the diag
collects the error, but `fy_diag_got_error` stays false. So a caller
can't use it to tell this failure from the end of the stream, as it
can for a syntax error. `fy_parser_get_stream_error` does return
true. `fy_document_build_from_string` with the same input and config
sets `fy_diag_got_error`, so the two paths disagree. Nothing is printed
to standard error in this case.

Repro, `alias.c`:

```c
/* libfyaml: a resolve failure in fy_parse_load_document collects an
   error but leaves fy_diag_got_error false. */
#include <stdio.h>
#include <string.h>
#include <libfyaml.h>

int main(int argc, char **argv) {
  struct fy_diag *diag = fy_diag_create(NULL);
  fy_diag_set_collect_errors(diag, true);
  struct fy_parse_cfg cfg;
  memset(&cfg, 0, sizeof cfg);
  cfg.flags = FYPCF_RESOLVE_DOCUMENT;
  cfg.diag = diag;
  struct fy_parser *p = fy_parser_create(&cfg);
  fy_parser_set_string(p, argv[1], FY_NT);
  struct fy_document *d = fy_parse_load_document(p);
  printf("document: %s\nfy_diag_got_error: %d\nfy_parser_get_stream_error: %d\n",
         d ? "non-NULL" : "NULL", fy_diag_got_error(diag),
         fy_parser_get_stream_error(p));
  void *it = NULL;
  struct fy_diag_error *e;
  while ((e = fy_diag_errors_iterate(diag, &it)))
    printf("collected: %d:%d: %s\n", e->line, e->column, e->msg);
  if (d) fy_document_destroy(d);
  fy_parser_destroy(p);
  fy_diag_destroy(diag);
  return 0;
}
```

```sh
cc -o alias alias.c $(pkg-config --cflags --libs libfyaml)
./alias '- name: *nope'
./alias '- &a [*a]'
```

Output:

```
document: NULL
fy_diag_got_error: 0
fy_parser_get_stream_error: 1
collected: 1:10: invalid alias
document: NULL
fy_diag_got_error: 0
fy_parser_get_stream_error: 1
collected: 1:8: cyclic reference detected
```

In the Oberon bindings, `FyamlStreams` resolves unless given
`NoResolve`, and used `fy_diag_got_error` alone to tell an error from
the end, so it ended the stream quietly, with no error. That is bug 1
in `POLIBFYAML-BUGS.md` and `OLIBFYAML-BUGS.md`, fixed 2026-11-15 by
also checking `fy_parser_get_stream_error`, which is set for a syntax
error and a resolve failure alike, and not at a clean end. pobesm2_fmt2
and obesm2_fmt2 read files that way, so until they are rebuilt with the
fixed binding they print nothing for a file with an undefined alias and
exit with status 0. The Ada binding's
`Libfyaml.Documents.Streams` makes the same check, but its parser never
sets `FYPCF_RESOLVE_DOCUMENT`, so this can't happen there.
