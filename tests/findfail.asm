; findfail - run a program whose directory searches fail after the first
;
;   findfail PROGRAM.EXT [ARGUMENTS]
;
; Test helper, err2out.asm with an INT 21h hook: while PROGRAM runs,
; every "find next" (INT 21h 4Fh) fails with carry set and AX = 5
; (access denied), as a disk error in mid-search would.  "Find first"
; still works, so a wildcard sees its first match and then the error.
; As with err2out, standard error goes to standard output, so the tests
; run "findfail cat.exe ARGS >file" to capture both streams.  The rest
; of the command tail, starting with the blank before ARGUMENTS, is
; passed to PROGRAM unchanged.  The exit status is PROGRAM's, or 255 if
; it could not be run.
;
; Build: nasm -f bin -o findfail.com findfail.asm

        cpu     8086
        org     100h

start:
        mov     sp, stack_top

        ; a .COM program owns all free memory; give back what we do not
        ; use so that there is room to run PROGRAM
        mov     bx, stack_top + 15
        mov     cl, 4
        shr     bx, cl                  ; paragraphs from the PSP
        mov     ah, 4Ah                 ; resize memory block (ES = PSP)
        int     21h
        jc      fail

        ; PROGRAM is the first blank-delimited word of the command tail
        mov     si, 81h
        mov     cl, [80h]
        xor     ch, ch
.skip:  jcxz    .none
        lodsb
        dec     cx
        cmp     al, ' '
        je      .skip
        cmp     al, 9
        je      .skip
        dec     si
        inc     cx
        jmp     .found
.none:  jmp     fail                    ; no PROGRAM
.found: mov     di, progname
.name:  jcxz    .named
        lodsb
        cmp     al, ' '
        je      .blank
        cmp     al, 9
        je      .blank
        stosb
        dec     cx
        jmp     .name
.blank: dec     si
.named: mov     byte [di], 0

        ; the rest of the tail, CR-terminated, is PROGRAM's tail
        mov     di, tail
        mov     al, cl
        stosb
        rep     movsb
        mov     al, 0Dh
        stosb

        ; make handle 2 (stderr) refer to the same file as handle 1
        mov     ah, 46h
        mov     bx, 1
        mov     cx, 2
        int     21h
        jc      fail

        ; hook INT 21h for PROGRAM
        mov     ax, 3521h
        int     21h
        mov     [old21], bx
        mov     [old21 + 2], es
        push    cs                      ; EXEC needs ES = CS again
        pop     es
        mov     dx, int21
        mov     ax, 2521h
        int     21h

        mov     [pb_tail + 2], cs
        mov     [pb_fcb1 + 2], cs
        mov     [pb_fcb2 + 2], cs
        mov     [save_sp], sp
        mov     dx, progname
        mov     bx, pblock
        mov     ax, 4B00h               ; load and execute
        int     21h

        ; DOS 2.x keeps only CS:IP across EXEC
        cli
        mov     ax, cs
        mov     ss, ax
        mov     sp, [cs:save_sp]
        sti
        mov     ds, ax
        mov     es, ax
        pushf
        push    ds
        lds     dx, [old21]             ; unhook (flags kept for jc)
        mov     ax, 2521h
        int     21h
        pop     ds
        popf
        jc      fail

        mov     ah, 4Dh                 ; AL = PROGRAM's exit status
        int     21h
        mov     ah, 4Ch
        int     21h

fail:   mov     ax, 4CFFh
        int     21h

; INT 21h while PROGRAM runs: 4Fh fails, everything else is DOS's
int21:  cmp     ah, 4Fh
        je      .fail
        jmp     far [cs:old21]
.fail:  mov     ax, 5
        push    bp
        mov     bp, sp
        or      word [bp + 6], 1        ; carry in the caller's flags
        pop     bp
        iret

old21:   dd     0
pblock:  dw     0                       ; inherit the environment
pb_tail: dw     tail, 0
pb_fcb1: dw     5Ch, 0
pb_fcb2: dw     6Ch, 0

        section .bss
save_sp:  resw  1
progname: resb  128
tail:     resb  128
        resb    256
stack_top:
