# cat16

A POSIX-style `cat` for 16-bit real-mode DOS, built with Open Watcom
and [libc16](https://github.com/gr-dos/libc16).

`cat.exe` is a small-model 8086 executable (about 5 KB on disk, 12 KB
of conventional memory) that runs on any DOS from 2.0 and an original
PC up. It copies files, or its standard input, to standard output byte
for byte, and expands DOS wildcards itself, since `COMMAND.COM` does
not. It is not a GNU coreutils clone: the formatting switches (`-n`,
`-b`, `-s`, `-v`, `-E`, `-T` and so on) are left out.

It follows the [gr-dos/hello16](https://github.com/gr-dos/hello16)
conventions, as a layout 1 (C only) utility.

## Usage

    cat [-u] [--] [FILE]...

    cat FILE                 copy FILE to standard output
    cat A.TXT B.TXT >C.TXT   C.TXT is A.TXT then B.TXT, nothing between
    cat *.TXT >ALL.OUT       every matching file, in name order
    cat >NEW.TXT             type the file; Ctrl+Z (or F6), Enter ends it
    cat                      copy standard input to standard output
    cat A.TXT - B.TXT        - is standard input, in its place
    cat --help               show help (also -h, -?)
    cat --version            show version

The exit status is 0 when everything was copied, and 1 if any input
could not be opened or read, a wildcard matched no file, the output
failed, or an option was bad.

**Never redirect the output to one of the inputs.** `COMMAND.COM`
creates (empties) the redirected file before `cat` runs, so
`cat A.TXT B.TXT >A.TXT` loses `A.TXT`. The same goes for wildcards,
which `cat` expands after the shell has already created the output:
`cat *.TXT >ALL.TXT` empties `ALL.TXT` and then copies it too. Use an
output name the pattern does not match, such as `cat *.TXT >ALL.OUT`.

### Operands

- **Files** are copied in command-line order, each to its end, with
  nothing added between them: no names, separators or newlines.
- **`-`** is standard input, wherever it appears among the operands.
  With no operands at all, `cat` copies standard input. Standard input
  is never reopened or rewound: a second `-` reads on from where the
  first stopped, so after redirected input has reached its end it
  copies nothing more, while at the console it reads what is typed
  next, as a Unix `cat` does at a terminal.
- **Wildcards.** An operand with `*` or `?` in its last part is a DOS
  wildcard, matched by DOS itself (INT 21h 4Eh/4Fh) as `DIR` matches it,
  in 8.3 names: `*.TXT`, `CH??.DOC`, `SUB\*.TXT`, `A:*.*`,
  `C:\NOTES\*.TXT`. `cat` collects the matches of each operand, sorts
  them by name ignoring case (ASCII order, `A` to `Z` folded to `a` to
  `z`), and copies them in that order. Operands stay in command-line
  order, so `cat FIRST.TXT *.DOC LAST.TXT` copies `FIRST.TXT`, the
  `.DOC` files in name order, then `LAST.TXT`. Wildcards match only
  ordinary files (read-only and archive ones too): never directories,
  the volume label, or hidden or system files, which `DIR` does not
  show either. Such a file can still be named in full. A wildcard is
  never taken as a literal name. A wildcard that matches nothing,
  whose directory does not exist, or with `*` or `?` before its last
  part (`S*\X.TXT`) is an error.
- **Errors in one operand** (a missing file, a directory, an unmatched
  wildcard) are reported on standard error, and `cat` goes on with the
  next operand; it exits with status 1 at the end.

### Options

- **`-u`** is accepted, as POSIX requires, and does nothing more:
  `cat` never holds output back, since each block it reads is written
  at once. It changes no byte and prints nothing. `-uu` is accepted too.
- **`--`** ends the options, so that a file whose name starts with `-`
  can be named: `cat -- -NOTE.TXT`.
- Options come before the operands (POSIX). After the first operand,
  everything is an operand: `cat A.TXT -u` is the files `A.TXT` and
  `-u`.
- `--help` (`-h`, `-?`) and `--version` are as in hello16. Any other
  option is an error (status 1, nothing copied).

### Bytes, and the end of the input

All input and output is DOS handle I/O (INT 21h 3Fh and 40h), with no
text-mode translation: CR, LF, NUL, bytes from 80h up and Ctrl+Z (1Ah)
in a disk file are copied like any other byte, and a disk file is
copied to its end, past any Ctrl+Z, whatever it holds. The same holds
for standard input redirected from a file (`cat <FILE`) or from a pipe,
which `COMMAND.COM` makes with a temporary file.

Input from a character device, such as the console, ends at a Ctrl+Z,
which is how DOS devices mark the end of input: `cat` copies what came
before it and stops. Typing at the console, DOS hands `cat` a line at a
time, when Enter is pressed, with the line's CR LF. So to end input,
type **Ctrl+Z, then Enter** (in MS-DOS, F6 types the Ctrl+Z too), on a
line of its own or after the last text, which is then copied without a
line ending. Ctrl+C or Ctrl+Break stops `cat` as it stops any DOS
program, with the input up to the last full line already written.

Output to the console is written as is too; what a device does with
control characters (CR, LF, bell, Ctrl+Z) is up to the device.

### Errors

Messages go to standard error as `cat: NAME: REASON`, for example
`cat: MISSING.TXT: No such file or directory`, `cat: SUB: Is a
directory`, `cat: NONE*.TXT: no matching files`, and
`cat: write error: No space left on device`. A write that fails, or
writes fewer bytes than asked (a full disk), ends `cat` at once with
status 1: there is no point copying further operands.

## Resources

`cat.exe` 0.01, linked with libc16 0.18:

| | Bytes |
|---|---|
| `cat.exe` file | 4,986 |
| Disk space, 360 KB floppy (1 KB clusters) | 5,120 |
| Disk space, 1.44 MB floppy (512-byte clusters) | 5,120 |
| Conventional memory to load (PSP 256 + image 4,938, to a paragraph 4,944, + BSS and stack 6,768) | 11,968 |
| of which the copy buffer | 4,096 |

Files are streamed through one fixed 4 KB buffer, whatever their size.
The only other memory is for wildcards: the names matched by one
operand are kept (13 bytes each, in a list that doubles as it grows,
from the near heap above the stack) while they are sorted, and freed
before the next operand: 3,328 bytes for a full 224-entry floppy root
directory. A wildcard matching more files than fit in what is left of
the small model's 64 KB data segment (several thousand), or more than
4,096, is reported as `Not enough memory`.

The sizes are from the `.EXE` header (`image` and `min alloc`) and
`cat.map`.

## Building

Everything is built and tested on a Linux host with GNU make, as in
hello16 (rule 1):

    make         # builds cat.exe
    make test    # runs the test suite under DOSBox-X
    make dist    # builds build/cat16-VERSION.zip
    make clean

`make` runs `scripts/fetch-libc16`, which downloads the pinned libc16
release, 0.18, checks its SHA-256 and unpacks it into `build/libc16`;
the release's `tools/fetch-watcom` then fetches the Open Watcom snapshot
libc16 names into `build/tools`. This needs `curl`, `unzip`,
`sha256sum` and `xz`. To use a local libc16 checkout built with its own
`make`:

    make LIBC16_ROOT=../libc16
    make test LIBC16_ROOT=../libc16

`cat.c` is compiled with libc16's consumer flags (its `docs/ABI.md`),
`wcc -zl -zld -x -ms -0 -s -bt=dos`, against libc16's headers only, and
linked with `wlink option nodefaultlibs`: no Open Watcom runtime. `-0`
means 8086 instructions only. The DOS calls it makes are all in libc16
(`_dos_open`, `_dos_read`, `_dos_write`, `_dos_findfirst` and so on).

To move to a newer libc16, set `version` and `sha256` in
`scripts/fetch-libc16` to the new release's, in the same change.

## Tests

`make test` runs `tests/run.sh` under a headless DOSBox-X, emulating an
8086 (`cputype=8086`). It needs `dosbox-x`, `nasm` (for the test
helpers) and `mtools` (for the floppy images). Set `KEEP=1` to keep the
work directory, and `DOSBOX=` for another DOSBox-X binary.

As in hello16, one batch file runs every DOS-side step, recording each
step's exit status and standard output, and the results are checked on
the host. Outputs are compared byte for byte with what the inputs
should give. The steps cover:

- files: text with LF and CR LF, a file of all 256 byte values plus
  NUL, Ctrl+Z, CR and LF runs, an empty file, a 20 KB file spanning
  several buffers, several files in one command;
- 300 matches of one wildcard, created in reverse order;
- wildcards: `*` and `?`, mixed-case host names, `SUB\*.TXT`,
  `C:\SUB\*.*`, `C:SUB\?.TXT`, wildcards mixed with plain files, an
  unmatched pattern (with a later file still copied), a missing
  directory, a wildcard in the directory part; and on a FAT floppy image
  whose files are in unsorted directory order, with a volume label, a
  subdirectory and hidden and system files matching the pattern: name
  order, and only the ordinary files;
- a directory and a missing file as operands;
- standard input redirected from a file and from a pipe, `-` among
  files, and `-` twice;
- `-u` with and without operands, `--`, a `-NAME` file, unknown
  options, `-u` after an operand, help and version (checked against
  `VERSION`);
- the console: keystrokes are put in the BIOS keyboard buffer by
  `tests/keys.asm`, so `cat` reads them from `CON` as typed text, ended
  by Ctrl+Z and Enter, on a line of its own, mid-line, and between
  files (DOSBox-X's own `AUTOTYPE` cannot type Ctrl+Z, and its console
  does not turn F6 into one as MS-DOS does);
- a full disk: a 200 KB file sent to a 160 KB floppy image fails with
  status 1;
- the diagnostics on standard error, captured with `tests/err2out.asm`
  (from hello16), since DOS shells cannot redirect standard error;
- the help topic: its header, plain ASCII, lines of at most 79
  columns.

The tests run under DOSBox-X only; on GR-DOS itself (QEMU or XT-class
hardware) they have not been run yet.

## GR-DOS help topic

`help/topics/CAT.txt` is `cat`'s topic for GR-DOS's `HELP CAT`, in the
format of GR-DOS's own `help/topics/*.txt`. The release archive carries
it at `help/topics/CAT.txt`, the path proposed in
[gr-dos/gr-dos#90](https://github.com/gr-dos/gr-dos/issues/90), so
that `dist16` can take the topic from the same pinned release as
`CAT.EXE`. Update it with any change of behavior.

## Conventions

These are hello16's (see its README for the full text).

- **`main` is protected:** it changes only by a merged pull request,
  the `test` check of `ci.yml` must pass, administrators included, and
  force pushes and deletion are not allowed.
- **CI** (`.github/workflows/ci.yml`) builds, runs `make test` and
  `make dist` on every pull request and every push to `main`.
- **`--version`** prints `cat (dos-cat16) VERSION`, the one line of
  `VERSION`, compiled in by the `Makefile`. Versions are MS-DOS style:
  `0.01`, `0.02`, ... `1.00`.
- **Releases** (`.github/workflows/release.yml`): on a push to `main`
  (a merge) whose `VERSION` has no `v<VERSION>` tag yet, the workflow
  builds and tests, tags the commit, and publishes a release with
  `cat.exe` and `cat16-VERSION.zip` (`cat.exe`, `help/topics/CAT.txt`,
  `README.md`, `VERSION`, `LICENSE` and libc16's license as
  `LICENSE.libc16`). To release, bump `VERSION` in the PR.

## Files

- `cat.c`: the program
- `Makefile`: Open Watcom and libc16 build (`make`, `make test`,
  `make dist`, `make clean`)
- `scripts/fetch-libc16`: fetch the pinned libc16 release
- `VERSION`: the version, compiled in and printed by `--version`
- `help/topics/CAT.txt`: the GR-DOS help topic
- `tests/run.sh`: the test suite, run under DOSBox-X by `make test`
- `tests/err2out.asm`, `tests/keys.asm`: 8086 test helpers (stderr
  capture, typed keystrokes)
- `.github/workflows/ci.yml`: build and test on PRs and pushes to `main`
- `.github/workflows/release.yml`: tag and release when `VERSION` changes

## License

MIT. See `LICENSE`. `cat.exe` includes code from libc16, also MIT.
