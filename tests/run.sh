#!/bin/sh
#
# Test cat.exe under DOSBox-X.
#
# One batch file runs every DOS-side step, and the results are checked
# on the host afterwards.  Each step N records cat's exit status in
# RN.OUT and its standard output in ON.OUT (.OUT, so that the outputs
# never match the tests' *.TXT wildcards).  rc.bat uses goto rather than
# "if errorlevel N echo ... >file" because the DOSBox-X shell opens the
# redirection even when the test is false.
#
# Helpers, built from tests/*.asm by make (their directory is the
# second argument):
#   err2out.com  runs cat with standard error sent to standard output,
#                since DOS shells cannot redirect standard error, so
#                that diagnostics can be checked
#   keys.com     puts keystrokes in the BIOS keyboard buffer ("~" is
#                Enter, "^" is Ctrl+Z), so that cat reads them from the
#                console (CON), not from a redirected file
#
# Two floppy images (mtools) are mounted as well: A: holds files written
# in an unsorted directory order, with a volume label, a subdirectory,
# a hidden and a system file, for the wildcard rules; B: is a 160 KB
# disk that is too small for BIG2.DAT, for the full-disk error.
#
# To add a test: add a step to steps.bat (command, then "call rc N")
# and the matching rc/same/check lines below.
#
# Usage: tests/run.sh [path/to/cat.exe [helper-dir]]
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/cat.exe}
helpers=${2:-$top/build}
DOSBOX=${DOSBOX:-dosbox-x}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
for t in mformat mcopy mmd mattrib; do
    command -v $t >/dev/null || { echo "$t (mtools) not found" >&2; exit 2; }
done
for f in "$exe" "$helpers/err2out.com" "$helpers/keys.com"; do
    [ -f "$f" ] || { echo "$f not found" >&2; exit 2; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/doscat.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures

cd "$work" || exit 2
mkdir c
cp "$exe" c/cat.exe
cp "$helpers/err2out.com" "$helpers/keys.com" c/

# Host names in mixed case: DOS sees them in upper case.
printf 'alpha\n' > c/a.txt                      # LF only
printf 'ab\r\n' > c/AB.TXT
printf 'bravo\r\n' > c/B.txt                    # CR LF
printf 'charlie' > c/c.TXT                      # no newline
: > c/EMPTY.DAT
printf 'dash\n' > c/-DASH.DAT
mkdir c/DIR.TXT                                 # a directory *.TXT matches
mkdir c/SUB
printf 'delta\n' > c/SUB/D.TXT
printf 'echo\n' > c/SUB/E.TXT

# Many matches for one wildcard, created in reverse order: the name
# list grows past several doublings.
mkdir c/MANY
i=300
while [ $i -gt 0 ]; do
    printf '%d\n' $i > c/MANY/F$(printf %03d $i).DAT
    i=$((i - 1))
done

# Every byte value, then the ones that text-mode I/O would change.
i=0
while [ $i -lt 256 ]; do
    printf "\\$(printf %03o $i)"
    i=$((i + 1))
done > c/BIN.DAT
printf '\0\032\r\n\n\r\032\032\0\377\200' >> c/BIN.DAT

# Several 4 KB buffers and a part; and too big for a 160 KB floppy.
head -c 20011 /dev/urandom > c/BIG.DAT
head -c 200000 /dev/urandom > c/BIG2.DAT

# A: a 720 KB floppy, files copied in unsorted order, with a volume
# label that *.* would match as a name, a subdirectory, and hidden and
# system files.
printf 'zulu\n' > zulu.txt
printf 'alpha\n' > alpha.txt
printf 'mike\n' > mike.txt
printf 'hidden\n' > hid.txt
printf 'system\n' > sys.txt
mformat -C -f 720 -v LABEL.TXT -i a.img :: >/dev/null || exit 2
for f in zulu.txt hid.txt alpha.txt sys.txt mike.txt; do
    mcopy -i a.img $f ::$(echo $f | tr a-z A-Z) || exit 2
done
mmd -i a.img ::SUBDIR.TXT || exit 2
mattrib -i a.img +h ::HID.TXT || exit 2
mattrib -i a.img +s ::SYS.TXT || exit 2

# B: a 160 KB floppy, nearly empty.
mformat -C -f 160 -i b.img :: >/dev/null || exit 2

cat > c/rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.out
goto end
:rc1
echo rc1 >c:\r%1.out
goto end
:rc2
echo rc2 >c:\r%1.out
:end
EOS

cat > c/steps.bat <<'EOS'
@echo off
rem --- files, byte for byte
cat a.txt >o1.out
call rc 1
cat a.txt B.TXT >o2.out
call rc 2
cat BIN.DAT >o3.out
call rc 3
cat BIG.DAT >o4.out
call rc 4
cat EMPTY.DAT >o5.out
call rc 5
cat EMPTY.DAT BIN.DAT EMPTY.DAT BIG.DAT c.txt >o6.out
call rc 6
rem --- wildcards
cat *.TXT >o7.out
call rc 7
cat ?.txt >o8.out
call rc 8
cat SUB\*.TXT >o9.out
call rc 9
cat C:\SUB\*.* >o10.out
call rc 10
cat C:SUB\?.TXT >o11.out
call rc 11
cat C.TXT SUB\*.TXT A.TXT >o12.out
call rc 12
cat NONE*.TXT A.TXT >o13.out
call rc 13
cat NODIR\*.TXT >o14.out
call rc 14
cat S*B\D.TXT >o15.out
call rc 15
cat A:*.* >o16.out
call rc 16
cat a:\*.txt >o17.out
call rc 17
cat A:HID.TXT A:SYS.TXT >o18.out
call rc 18
rem --- errors on inputs
cat DIR.TXT >o19.out
call rc 19
cat MISSING.TXT B.TXT >o20.out
call rc 20
rem --- standard input, redirected
cat <BIN.DAT >o21.out
call rc 21
cat - <BIN.DAT >o22.out
call rc 22
cat B.TXT - C.TXT <A.TXT >o23.out
call rc 23
cat - A.TXT - <B.TXT >o24.out
call rc 24
cat BIN.DAT | cat >o25.out
call rc 25
rem --- options
cat -u A.TXT >o26.out
call rc 26
cat -u <BIN.DAT >o27.out
call rc 27
cat -uu -- -DASH.DAT >o28.out
call rc 28
cat -DASH.DAT >o29.out
call rc 29
cat --bogus A.TXT >o30.out
call rc 30
cat -x A.TXT >o31.out
call rc 31
cat --help >o32.out
call rc 32
cat -h >o33.out
call rc 33
cat -? >o34.out
call rc 34
cat --version >o35.out
call rc 35
cat A.TXT -u >o36.out
call rc 36
rem --- the console: keys typed, Ctrl+Z and Enter to end
keys hi~there~^~
cat >o37.out
call rc 37
keys ab^~
cat -u >o38.out
call rc 38
keys x~^~y~^~
cat - - >o39.out
call rc 39
keys mid~^~
cat A.TXT - B.TXT >o40.out
call rc 40
rem --- a full disk
cat BIG2.DAT >B:\OUT.DAT
call rc 41
rem --- diagnostics on standard error
err2out cat.exe MISSING.TXT >o42.out
call rc 42
err2out cat.exe DIR.TXT >o43.out
call rc 43
err2out cat.exe NONE*.TXT >o44.out
call rc 44
err2out cat.exe -x >o45.out
call rc 45
err2out cat.exe S*B\D.TXT >o46.out
call rc 46
err2out cat.exe A.TXT NODIR\*.TXT B.TXT >o47.out
call rc 47
rem --- a wildcard with many matches
cat MANY\F*.DAT >o48.out
call rc 48
EOS

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cputype=8086" -set "cpu cycles=max" \
    -c "mount c \"$work/c\"" \
    -c "imgmount a \"$work/a.img\" -t floppy" \
    -c "imgmount b \"$work/b.img\" -t floppy" \
    -c "c:" -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

cd c || exit 2

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# check NAME COMMAND...
check() {
    name=$1
    shift
    if "$@"; then ok; else not_ok "$name"; fi
}

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.OUT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# same STEP FILE...; ON.OUT must be exactly the FILEs' bytes, in order
# (none: empty)
same() {
    n=$1
    shift
    cat -- "$@" < /dev/null > ../want.bin
    if [ ! -f "O$n.OUT" ]; then
        not_ok "step $n: no output file"
    elif cmp -s "O$n.OUT" ../want.bin; then
        ok
    else
        not_ok "step $n: output differs"
        cmp "O$n.OUT" ../want.bin | sed 's/^/    /'
    fi
}

# bytes STEP PRINTF-FORMAT; ON.OUT must be exactly these bytes
bytes() {
    printf "$2" > ../want.txt
    same "$1" ../want.txt
}

# says STEP TEXT; ON.OUT (stdout and stderr) has the line TEXT
says() {
    if tr -d '\r' < "O$1.OUT" 2>/dev/null | grep -qxF "$2"; then
        ok
    else
        not_ok "step $1: no line '$2'"
        sed 's/^/    /' "O$1.OUT" 2>/dev/null
    fi
}

# files, byte for byte
rc 1 0;  same 1 a.txt
rc 2 0;  same 2 a.txt B.txt
rc 3 0;  same 3 BIN.DAT
rc 4 0;  same 4 BIG.DAT
rc 5 0;  same 5
rc 6 0;  same 6 BIN.DAT BIG.DAT c.TXT

# wildcards: case-insensitive name order, no directories, no separators
rc 7 0;  same 7 a.txt AB.TXT B.txt c.TXT
rc 8 0;  same 8 a.txt B.txt c.TXT
rc 9 0;  same 9 SUB/D.TXT SUB/E.TXT
rc 10 0; same 10 SUB/D.TXT SUB/E.TXT
rc 11 0; same 11 SUB/D.TXT SUB/E.TXT
rc 12 0; same 12 c.TXT SUB/D.TXT SUB/E.TXT a.txt
rc 13 1; same 13 a.txt
rc 14 1; same 14
rc 15 1; same 15
# A: sorted, without the label, SUBDIR.TXT, HID.TXT or SYS.TXT
rc 16 0; same 16 ../alpha.txt ../mike.txt ../zulu.txt
rc 17 0; same 17 ../alpha.txt ../mike.txt ../zulu.txt
rc 18 0; same 18 ../hid.txt ../sys.txt

# errors on inputs: later operands still copied
rc 19 1; same 19
rc 20 1; same 20 B.txt

# standard input, redirected: bytes unchanged, read once
rc 21 0; same 21 BIN.DAT
rc 22 0; same 22 BIN.DAT
rc 23 0; same 23 B.txt a.txt c.TXT
rc 24 0; same 24 B.txt a.txt
rc 25 0; same 25 BIN.DAT

# options
rc 26 0; same 26 a.txt
rc 27 0; same 27 BIN.DAT
rc 28 0; same 28 -DASH.DAT
rc 29 1; same 29
rc 30 1; same 30
rc 31 1; same 31
rc 32 0
check "step 32: help" grep -q '^Usage: cat \[-u\] \[FILE\]' O32.OUT
rc 33 0
check "step 33: -h same as --help" cmp -s O32.OUT O33.OUT
rc 34 0
check "step 34: -? same as --help" cmp -s O32.OUT O34.OUT
rc 35 0
check "step 35: version" test "$(tr -d '\r' < O35.OUT)" = \
    "cat (dos-cat16) $(cat "$top/VERSION")"
# after an operand, -u is a file name (POSIX)
rc 36 1; same 36 a.txt

# the console: DOS echoes nothing into the file; CR LF per line; ^Z ends
rc 37 0; bytes 37 'hi\r\nthere\r\n'
rc 38 0; bytes 38 'ab'
# each - reads the console again, as a terminal would
rc 39 0; bytes 39 'x\r\ny\r\n'
rc 40 0; bytes 40 'alpha\nmid\r\nbravo\r\n'

# a full disk
rc 41 1

# diagnostics
rc 42 1; says 42 'cat: MISSING.TXT: No such file or directory'
rc 43 1; says 43 'cat: DIR.TXT: Is a directory'
rc 44 1; says 44 'cat: NONE*.TXT: no matching files'
rc 45 1; says 45 "cat: invalid option '-x'"
rc 46 1; says 46 'cat: S*B\D.TXT: wildcards are allowed only in the file name'
rc 47 1; says 47 'cat: NODIR\*.TXT: No such file or directory'
check "step 47: later operand copied" grep -q '^bravo' O47.OUT
rc 48 0; same 48 $(i=1; while [ $i -le 300 ]; do printf 'MANY/F%03d.DAT ' $i; i=$((i + 1)); done)

# the GR-DOS help topic (gr-dos/gr-dos#90): its header, plain ASCII,
# and lines that fit an 80-column screen
topic=$top/help/topics/CAT.txt
check "help topic: header" test "$(sed -n 1p "$topic")" = "Topic: CAT"
check "help topic: Files" grep -qx 'Files: CAT.EXE' "$topic"
check "help topic: ASCII" sh -c "! LC_ALL=C grep -q '[^ -~]' '$topic'"
check "help topic: width" sh -c "! awk 'length(\$0) > 79' '$topic' | grep -q ."

# ------------------------------------------------------------------

cd ..
echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
