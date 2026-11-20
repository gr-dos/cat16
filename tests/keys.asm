; keys - type keystrokes, for the console-input tests
;
;   keys TEXT
;
; Test helper.  Puts each character of TEXT in the BIOS keyboard buffer
; (INT 16h 05h), so that the next program reading the console gets them
; as if typed: "~" is Enter (CR), "^" is Ctrl+Z (1Ah), and every other
; character is itself.  Blanks are skipped.  The buffer holds 15 keys.
; INT 16h 05h is an AT BIOS service; DOSBox-X has it, an XT BIOS does not.
;
; Build: nasm -f bin -o keys.com keys.asm

        cpu     8086
        org     100h

        mov     si, 81h
next:   lodsb
        cmp     al, 0Dh                 ; end of the command tail
        je      done
        cmp     al, ' '
        je      next
        mov     ch, 0                   ; CH: scan code, CL: character
        mov     cl, al
        cmp     al, '~'
        jne     .ctrlz
        mov     cx, 1C0Dh               ; Enter
.ctrlz: cmp     al, '^'
        jne     .type
        mov     cx, 2C1Ah               ; Ctrl+Z
.type:  mov     ah, 05h
        int     16h
        jmp     next

done:   mov     ax, 4C00h
        int     21h
