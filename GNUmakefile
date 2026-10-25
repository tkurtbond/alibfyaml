# Builds and installs the library.  gprinstall copies whatever lib/
# holds without building it, so a checkout pulled but not rebuilt
# installs new sources beside .ali files compiled from the old ones,
# and a program built against them can fail to bind ("... must be
# recompiled").  install builds first so the two always match.
#
#   make install GPRINSTALL=tkbgprinstall    # or gprinstall --prefix=DIR

GPRINSTALL ?= gprinstall

.PHONY: build install

build:
	gprbuild -p -P libfyaml_ada.gpr

install: build
	$(GPRINSTALL) -f -p -P libfyaml_ada.gpr
