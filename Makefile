# Build cat.exe for 16-bit MS-DOS with Open Watcom and libc16.
#   make                         fetch the pinned libc16 release into
#                                build/libc16, then build cat.exe
#   make LIBC16_ROOT=../libc16   use a libc16 checkout built with its make
#
# cat.exe is compiled and linked against libc16 only (its ABI is in
# libc16's docs/ABI.md), with the Open Watcom snapshot libc16 was built
# with: the libc16 tree's tools/fetch-watcom fetches it into build/tools.

LIBC16_ROOT ?= build/libc16
# A release tree, or a checkout, whose make stages the same layout in
# build/stage.
LIBC16_DIR  := $(if $(wildcard $(LIBC16_ROOT)/build/stage/VERSION),$(LIBC16_ROOT)/build/stage,$(LIBC16_ROOT))
LIBC16      := $(LIBC16_DIR)/lib/LIBC16.LIB
TOOLS_ENV   := build/tools.env
WATCOM_ENV   = . ./$(TOOLS_ENV) && PATH=$$WATCOM/binl64:$$PATH

VERSION := $(shell cat VERSION)

CC     = wcc
CFLAGS = -q -zq -zl -zld -x -ms -0 -os -s -bt=dos -wx -we \
         -I$(LIBC16_DIR)/include '-DVERSION="$(VERSION)"'

cat.exe: cat.obj $(LIBC16) $(TOOLS_ENV)
	$(WATCOM_ENV) && wlink option quiet, nodefaultlibs, map=cat.map \
	  format dos name $@ file cat.obj library $(LIBC16)

cat.obj: cat.c VERSION $(LIBC16) $(TOOLS_ENV)
	$(WATCOM_ENV) && $(CC) $(CFLAGS) -fo=$@ cat.c

# The pinned libc16 release (scripts/fetch-libc16). A LIBC16_ROOT given
# on the command line must already be built.
ifeq ($(LIBC16_ROOT),build/libc16)
$(LIBC16): scripts/fetch-libc16
	scripts/fetch-libc16 $(LIBC16_ROOT)
endif

# The Open Watcom snapshot libc16 names, as shell assignments.
$(TOOLS_ENV): $(LIBC16)
	mkdir -p build
	watcom=$$(sh $(LIBC16_DIR)/tools/fetch-watcom $(CURDIR)/build/tools) \
	  && printf 'WATCOM=%s\nexport WATCOM\n' "$$watcom" > $@

# Test helpers (8086 .COM programs), assembled with NASM.
NASM   ?= nasm
HELPERS = build/err2out.com build/keys.com

build/%.com: tests/%.asm
	mkdir -p build
	$(NASM) -f bin -Werror -o $@ $<

test: cat.exe $(HELPERS)
	sh tests/run.sh $(CURDIR)/cat.exe $(CURDIR)/build

# The release archive: the program, its GR-DOS help topic (the path
# gr-dos/gr-dos#90 proposes), and the notices.
DIST = build/cat16-$(VERSION).zip

dist: $(DIST)

$(DIST): cat.exe help/topics/CAT.txt README.md LICENSE VERSION $(LIBC16)
	rm -rf build/dist $@
	mkdir -p build/dist/help/topics
	cp cat.exe README.md LICENSE VERSION build/dist/
	cp help/topics/CAT.txt build/dist/help/topics/
	cp $(LIBC16_DIR)/LICENSE build/dist/LICENSE.libc16
	cd build/dist && zip -q -X -r ../cat16-$(VERSION).zip .

clean:
	rm -f *.o *.obj *.err *.map cat.exe

.PHONY: test dist clean
