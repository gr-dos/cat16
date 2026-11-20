/*
 * cat - concatenate files to standard output
 *
 * A POSIX-style cat for 16-bit real-mode DOS (Open Watcom C with
 * libc16), for the 8086 and up.
 *
 *   cat [-u] [file ...]
 *
 * Each operand is copied to standard output in order, byte for byte,
 * through one fixed 4 KB buffer.  "-" is standard input, as is no
 * operand at all.  An operand with * or ? in its last part is a DOS
 * wildcard, expanded here (COMMAND.COM does not), its matches copied in
 * case-insensitive name order.
 *
 * All file I/O is DOS handle I/O (INT 21h 3Fh/40h), so nothing is
 * translated: CR, LF and ^Z in a disk file are copied like any other
 * byte.  Only input from a character device (the console, AUX) ends at
 * a ^Z, which is how DOS devices mark the end of input.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dos.h>

#ifndef VERSION
#define VERSION   "unknown"
#endif

#define BUFSIZE   4096          /* the copy buffer */
#define PATHMAX   128           /* a DOS path, with its terminator */
#define NAMELEN   13            /* an 8.3 name, with its terminator */
#define MAXNAMES  4096          /* names one wildcard may match */
#define CTRL_Z    0x1A

static const char *progname = "cat";

static unsigned char buf[BUFSIZE];
static char path[PATHMAX + NAMELEN];
static int status = 0;

/* Writes "cat: NAME: TEXT" to standard error. */
static void complain(const char *name, const char *text)
{
    fputs(progname, stderr);
    fputs(": ", stderr);
    if (name != NULL) {
        fputs(name, stderr);
        fputs(": ", stderr);
    }
    fputs(text, stderr);
    fputs("\n", stderr);
}

/* As complain, and remembers that cat failed. */
static void fail(const char *name, const char *text)
{
    complain(name, text);
    status = 1;
}

/* Writes "cat: WHAT 'ARG'" and the --help hint to standard error. */
static void bad_arg(const char *what, const char *arg)
{
    fputs(progname, stderr);
    fputs(": ", stderr);
    fputs(what, stderr);
    fputs(" '", stderr);
    fputs(arg, stderr);
    fputs("'\n", stderr);
    fputs("Try 'cat --help' for more information.\n", stderr);
}

static void usage(FILE *fp)
{
    fputs(
        "Usage: cat [-u] [FILE]...\n"
        "Concatenate FILEs to standard output.\n"
        "\n"
        "With no FILE, or when FILE is -, read standard input.\n"
        "A FILE with * or ? in its name is a DOS wildcard; its matching\n"
        "files are copied in name order.\n"
        "\n"
        "  -u             unbuffered output (always the case; accepted)\n"
        "  -h, --help     display this help and exit\n"
        "      --version  output version information and exit\n"
        "  --             end of options: later arguments are FILEs\n"
        "\n"
        "Bytes are copied unchanged.  From the console, Ctrl+Z then Enter\n"
        "ends input.  Do not redirect to a file that is also an input.\n",
        fp);
}

/* Writes all N bytes at P to standard output, or exits: once output has
   failed there is nothing more cat can usefully do. */
static void put(const unsigned char *p, unsigned n)
{
    unsigned done;

    while (n > 0) {
        if (_dos_write(1, p, n, &done) != 0) {
            complain("write error", strerror(errno));
            exit(1);
        }
        if (done == 0) {        /* DOS writes short on a full disk */
            complain("write error", strerror(ENOSPC));
            exit(1);
        }
        p += done;
        n -= done;
    }
}

/* Whether handle H is a character device (INT 21h 4400h, DX bit 7). */
static int is_device(int h)
{
    union REGS r;

    r.x.ax = 0x4400;
    r.x.bx = h;
    intdos(&r, &r);
    return !r.x.cflag && (r.x.dx & 0x80) != 0;
}

/* Copies handle H, named NAME in messages, to standard output, until the
   end of the file, or for a device a ^Z. */
static void copy(int h, const char *name)
{
    int dev = is_device(h);
    unsigned n;
    unsigned char *z;

    for (;;) {
        if (_dos_read(h, buf, BUFSIZE, &n) != 0) {
            fail(name, strerror(errno));
            return;
        }
        if (n == 0)
            return;
        if (dev && (z = memchr(buf, CTRL_Z, n)) != NULL) {
            put(buf, (unsigned)(z - buf));
            return;
        }
        put(buf, n);
    }
}

/* Copies the file NAME (no wildcards) to standard output. */
static void cat_file(const char *name)
{
    int h;
    int e;
    unsigned attr;

    if (_dos_open(name, 0, &h) != 0) {      /* 0: read only */
        e = errno;
        if (_dos_getfileattr(name, &attr) == 0 && (attr & _A_SUBDIR))
            fail(name, "Is a directory");
        else
            fail(name, strerror(e));
        return;
    }
    copy(h, name);
    _dos_close(h);
}

static int __cdecl by_name(const void *a, const void *b)
{
    return stricmp((const char *)a, (const char *)b);
}

/* Expands the wildcard PAT, whose last part starts at BASE, and copies
   each regular file it matches, in name order. */
static void cat_wild(const char *pat, const char *base)
{
    struct find_t f;
    char *names = NULL;
    char *more;
    unsigned count = 0;
    unsigned room = 0;
    unsigned dir = (unsigned)(base - pat);
    unsigned i;
    unsigned err;

    for (i = 0; i < dir; i++) {
        if (pat[i] == '*' || pat[i] == '?') {
            fail(pat, "wildcards are allowed only in the file name");
            return;
        }
    }
    if (strlen(pat) >= PATHMAX) {
        fail(pat, "path too long");
        return;
    }

    /* Attribute 0: normal, read-only and archive files only; DOS leaves
       out hidden and system files, directories and the volume label. */
    err = _dos_findfirst(pat, 0, &f);
    if (err != 0 && err != 2 && err != 18) {    /* 2, 18: no match */
        fail(pat, strerror(errno));             /* 3: no such path */
        return;
    }
    for (; err == 0; err = _dos_findnext(&f)) {
        if (f.attrib & (_A_SUBDIR | _A_VOLID | _A_HIDDEN | _A_SYSTEM))
            continue;
        if (count == room) {
            room = room == 0 ? 16 : room < MAXNAMES / 2 ? room * 2 : MAXNAMES;
            more = count < MAXNAMES ? realloc(names, room * NAMELEN) : NULL;
            if (more == NULL) {
                free(names);
                fail(pat, strerror(ENOMEM));
                return;
            }
            names = more;
        }
        memcpy(names + count * NAMELEN, f.name, NAMELEN);
        names[count * NAMELEN + NAMELEN - 1] = '\0';
        count++;
    }
    if (count == 0) {
        fail(pat, "no matching files");
        return;
    }

    qsort(names, count, NAMELEN, by_name);
    memcpy(path, pat, dir);
    for (i = 0; i < count; i++) {
        strcpy(path + dir, names + i * NAMELEN);
        cat_file(path);
    }
    free(names);
}

/* Copies operand ARG: "-" for standard input, a wildcard, or a file. */
static void cat_operand(const char *arg)
{
    const char *base = arg;
    const char *p;

    if (strcmp(arg, "-") == 0) {
        copy(0, "-");
        return;
    }
    for (p = arg; *p != '\0'; p++) {
        if (*p == '\\' || *p == '/' || *p == ':')
            base = p + 1;
    }
    if (strpbrk(arg, "*?") != NULL)
        cat_wild(arg, base);
    else
        cat_file(arg);
}

int main(int argc, char **argv)
{
    int i;
    int operands = 0;
    const char *p;

    /* Options come before the first operand (POSIX); "--" ends them. */
    for (i = 1; i < argc; i++) {
        const char *a = argv[i];

        if (a[0] != '-' || a[1] == '\0')
            break;                          /* an operand, or "-" */
        if (strcmp(a, "--") == 0) {
            i++;
            break;
        }
        if (strcmp(a, "--help") == 0) {
            usage(stdout);
            return 0;
        }
        if (strcmp(a, "--version") == 0) {
            fputs("cat (dos-cat16) " VERSION "\n", stdout);
            return 0;
        }
        if (a[1] == '-') {
            bad_arg("unrecognized option", a);
            return 1;
        }
        for (p = a + 1; *p != '\0'; p++) {
            if (*p == 'h' || *p == '?') {
                usage(stdout);
                return 0;
            }
            if (*p != 'u') {                /* -u: output is unbuffered */
                bad_arg("invalid option", a);
                return 1;
            }
        }
    }

    for (; i < argc; i++) {
        cat_operand(argv[i]);
        operands++;
    }
    if (operands == 0)
        copy(0, "-");
    return status;
}
