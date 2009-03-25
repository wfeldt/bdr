; test_03
;
; Read [sector_count = 0x1ba] blocks starting at 0 from disk 0x81 and
; compare with disk 0x80 starting at [sector_start = 0x1b6].
;
; Use various block sizes.
; Use CHS interface.
;

			bits 16

			%include "x86emu.inc"

			section .text

			org 7c00h

			jmp 0:main_10
main_10:
			mov ax,cs
			mov ss,ax
			xor sp,sp
			mov ds,ax
			mov es,ax
			cld
			sti

			mov [edd.drive],dl

;			x86emu_trace_on x86emu_trace_default

			call disk_read

			mov si,msg_hello
			call print

			call check

			mov si,msg_check_failed
			jc main_30
			mov si,msg_check_ok
main_30:

			jmp final_msg


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
disk_read:

			; classic interface; but if block number turns out
			; to be too big, try edd anyway

			cmp dword [edd.sector+4],0
			jnz disk_read_chs_90
			mov ah,8
			xor di,di
			call int_13
			jc disk_read_chs_90

			mov ax,cx
			shr cl,6
			xchg cl,ch
			and al,3fh
			inc dh
			mov bl,al
			mul dh
			; ax = s*h
			xchg ax,di
			mov ax,[edd.sector]
			mov dx,[edd.sector+2]
;			x86emu_print "linear dx:ax"
;			x86emu_trace_on x86emu_trace_regs
;			x86emu_trace_off x86emu_trace_regs
			cmp dx,di
			jae disk_read_chs_90
			div di
			; ax = c, dx = s*h
			cmp ax,cx
			ja disk_read_chs_90
			shl ah,6
			xchg al,ah
			xchg ax,dx
			; dx = c
			div bl
			; ah = s-1, al = h
			add dl,ah
			inc dx
			mov ch,al
			xchg cx,dx

			mov al,[edd.count]
			les bx,[edd.buf]
			mov ah,2
;			x86emu_print "chs"
;			x86emu_trace_on x86emu_trace_regs
;			x86emu_trace_off x86emu_trace_regs
			call int_13
			push word 0
			pop es
disk_read_chs_90:
			ret

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; CF: 0 = edd ok, 1 = no edd
;
edd_check:
			cmp byte [edd_checked],1
			jbe edd_check_90

			mov byte [edd_checked],0

			mov ah,41h
			mov bx,55aah
			call int_13
			jc edd_check
			cmp bx,0aa55h
			jnz edd_check
			test cl,1
			jz edd_check
			inc byte [edd_checked]
edd_check_90:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
int_13:
			mov dl,[edd.drive]
			push bp
			int 13h
			pop bp
			ret

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
final_msg:
			call print
			mov si,msg_done
			call print
			mov ah,0
			int 16h
			mov si,msg_nl
			call print
			int 19h

final_msg_10:
			hlt
			jmp final_msg_10

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Write string.
;
;  si			text
;
; return:
;
print:
			lodsb
			or al,al
			jz print_90
			cmp al,0ah
			jnz print_50
			mov ax,0e0dh
			mov bx,7
			int 10h
			mov al,0ah
print_50:
			mov bx,7
			mov ah,0eh
			int 10h
			jmp print
print_90:
			ret



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
			align 4

edd.packet		dw 10h
edd.count		dw prog_blocks
edd.buf			dw 7e00h, 0
edd.sector		dd 1, 0

edd.drive		db 0
edd_checked		db 2

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
%if ($ - $$) > 1b8h
%error "test_03 too big"
%endif

mbr_fill		times 1b6h - ($ - $$) db 0

sector_start		dd 0
sector_count		dd 0

			times 40h db 0

			dw 0aa55h


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
buf1_seg		equ 1000h
buf2_seg		equ 3000h

msg_nl			db 10
msg_no_msg		db 0
msg_done		db 10, "test_03 done", 0
msg_hello		db "starting test_03", 10, 0
msg_check_ok		db 'check ok', 10, 0
msg_check_failed	db 'check failed', 10, 0
msg_step		db 13, 'step ', 0

			align 4
cnt			dd 0
block_size		dd 0
block_sizes		db 1, 5, 7, 26, 32, 50, 64
block_sizes_end		equ $
step			db 0


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Print hex number.
;
hex2:
			push ax
			shr al,4
			call hex1
			pop ax
hex1:
			and al,0fh
			cmp al,9
			jbe hex1_20
			add al,7
hex1_20:
			add al,'0'
			mov si,hex1_buf
			mov [si],al
			jmp print

hex1_buf		db 0, 0


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
check:
			xor ax,ax
			xor di,di
			mov dx,buf1_seg
			mov bx,4
check_05:
			mov es,dx
			mov cx,8000h
			rep stosw
			add dx,1000h
			dec bx
			jnz check_05

check_07:
			mov dword [cnt],0

			movzx ebx,byte [step]
			mov al,[block_sizes+bx]
			mov [block_size],al

			mov si,msg_step
			call print
			mov ax,[step]
			call hex2

check_10:
			mov dword [edd.buf],buf1_seg << 16
			mov eax,[cnt]
			mov [edd.sector],eax
			push word [block_size]
			pop word [edd.count]
			call disk_read
			jc check_90

;			x86emu_print "read 1 ok"

			mov dword [edd.buf],buf2_seg << 16
			mov eax,[cnt]
			add eax,[sector_start]
			mov [edd.sector],eax
			push word [block_size]
			pop word [edd.count]
			mov dl,80h
			xchg dl,[edd.drive]
			push dx
			call disk_read
			pop dx
			mov [edd.drive],dl
			jc check_90

;			x86emu_print "read 2 ok"

			mov ax,[block_size]
			mov bx,buf1_seg
			mov dx,buf2_seg
check_50:
			xor si,si
			xor di,di
			mov cx,80h
			mov fs,bx
			mov es,dx
			fs repe cmpsd
			stc
			jnz check_90
			add bx,20h
			add dx,20h
			dec ax
			jnz check_50

;			x86emu_print "cmp ok"

			mov eax,[cnt]
			add eax,[block_size]
			mov [cnt],eax
			add eax,[block_size]
			cmp eax,[sector_count]

			jbe check_10

			inc byte [step]
			cmp byte [step],block_sizes_end - block_sizes
			jb check_07

check_90:
;			x86emu_trace_on x86emu_trace_default

			pushf
			mov si,msg_nl
			call print
			popf

			ret



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
prog_blocks		equ ($ - $$ + 511) >> 9

