; test_01
;
; Read [sector_count = 0x1ba] blocks starting at 0 from disk 0x81 and
; compare with disk 0x80 starting at [sector_start = 0x1b6].
;

			bits 16

			%include "x86emu.inc"

disk_buf		equ 8000h
disk_buf2		equ 8200h

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

			mov si,msg_hello
			call print

			call check
			mov si,msg_check_failed
			jc main_30
			mov si,msg_check_ok
main_30:

			jmp final_msg


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
check:
check_10:
			mov eax,[cnt]
			mov [edd.sector],eax
			mov word [edd.count],1
			call disk_read
			jc check_90

;			x86emu_reset_stats

			mov si,disk_buf
			mov di,disk_buf2
			mov cx,100h
			rep movsw

			mov eax,[cnt]
			add eax,[sector_start]
			mov [edd.sector],eax
			mov word [edd.count],1
			mov dl,80h
			xchg dl,[edd.drive]
			push dx
			call disk_read
			pop dx
			mov [edd.drive],dl

;			x86emu_print "sector2 ok"

;			x86emu_dump x86emu_dump_mem_default

			jc check_90

			mov si,disk_buf
			mov di,disk_buf2
			mov cx,100h
			repe cmpsb
			stc
			jnz check_90

			x86emu_trace_on x86emu_trace_default

			mov eax,[cnt]
			inc eax
			mov [cnt],eax
			cmp eax,[sector_count]

			jb check_10
check_90:
;			x86emu_trace_on x86emu_trace_default

			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
disk_read:
			mov dword [edd.buf],disk_buf << 12
			call edd_check
			jc disk_read_chs
disk_read_edd:
			mov si,edd.packet
			mov word [si],10h
			mov ah,42h
			jmp int_13


disk_read_chs:
			; classic interface; but if block number turns out
			; to be too big, try edd anyway

			cmp dword [edd.sector+4],0
			jnz disk_read_edd
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
			cmp dx,di
			jae disk_read_edd
			div di
			; ax = c, dx = s*h
			cmp ax,cx
			ja disk_read_edd
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
			mov bx,7
			mov ah,14
			int 10h
			jmp print
print_90:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
			align 4

edd.packet		dw 10h
edd.count		dw 1
edd.buf			dw 0, 0
edd.sector		dd 0, 0
edd.drive		db 0

cnt			dd 0

edd_checked		db 2

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
msg_nl			db 13, 10
msg_no_msg		db 0
msg_hello		db "starting test_01", 13, 10, 0
msg_done		db 10, "test_01 done", 0
msg_check_ok		db 'check ok', 13, 10, 0
msg_check_failed	db 'check failed', 13, 10, 0

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
%if ($ - $$) > 1b8h
%error "test_01 too big"
%endif

mbr_fill		times 1b6h - ($ - $$) db 0

sector_start		dd 0
sector_count		dd 0

			times 40h db 0

			dw 0aa55h
