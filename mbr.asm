			bits 16

			%include "bdr.inc"

			section .text

			org mbr_start

			jmp 0:main_10
main_10:
			mov ax,cs
			mov ss,ax
			xor sp,sp
			mov ds,ax
			mov es,ax
			cld
			sti

			mov bp,mbr_vars_start

			; first, try boot drive
			mov [bp+edd.drive],dl
			call check
			jz main_60

			mov ah,8
			xor di,di
			mov dl,80h
			call int_13
			jnc main_20
			mov dl,1		; we'll try at least one
main_20:
			cmp dl,1		; dto
			mov al,80h
			adc dl,al
			mov [bp+bios_drives],dl

main_30:
			mov [bp+edd.drive],al
			call check
			jz main_60
			mov al,[bp+edd.drive]
			inc ax
			cmp al,[bp+bios_drives]
			jb main_30

			; too bad, not found

			mov si,msg_not_found
			jmp final_msg

main_60:
			; ok, we got it

			mov si,msg_ok
			call print

			mov bx,disk_read
			call disk_buf + sht.sizeof + bht.sizeof

			mov si,msg_no_msg
			jmp final_msg


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; return:
;   ZF:		1 ok; 0 not ok
;

check:
			mov word [bp+edd.count],1
			mov si,start_sector
			lea di,[bp+edd.sector]
			movsd
			movsd
			call disk_read
			sbb cx,cx
			jnz check_90
			mov si,disk_buf+sht.id
			mov di,id
			mov cl,4		; cx was 0
			rep cmpsw
			jnz check_90
			xor dx,dx
			mov ch,1		; cx was 0
			mov si,disk_buf
check_50:
			lodsw
			add dx,ax
			loop check_50
check_90:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
disk_read:
			mov dword [bp+edd.buf],disk_buf << 12
			mov ah,41h
			mov bx,55aah
			call int_13
			jc disk_read_chs
			cmp bx,0aa55h
			jnz disk_read_chs
			test cl,1
			jz disk_read_chs
disk_read_edd:
			lea si,[bp+edd.packet]
			mov word [si],10h
			mov ah,42h
			jmp int_13


disk_read_chs:
			; classic interface; but if block number turns out
			; to be too big, try edd anyway

			cmp dword [bp+edd.sector+4],0
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
			mov ax,[bp+edd.sector]
			mov dx,[bp+edd.sector+2]
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

			mov al,[bp+edd.count]
			les bx,[bp+edd.buf]
			mov ah,2
			call int_13
			push word 0
			pop es
disk_read_chs_90:
			ret

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
int_13:
			mov dl,[bp+edd.drive]
			push bp
			int 13h
			pop bp
			ret

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
final_msg:
			call print
			mov si,msg_next
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
			; maybe save bp?
			int 10h
			jmp print
print_90:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
msg_ok			db "ok", 13, 10, 0
msg_not_found		db "Boot drive not found."
msg_nl			db 13, 10
msg_no_msg		db 0
msg_next		db 10, "Press a key to continue boot sequence.", 0

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
%if ($ - $$) > 1a8h
%error "mbr too big"
%endif

mbr_fill		times 1a8h - ($ - $$) db 0

start_sector		dd 0, 0
id			dd 0, 0

			times 1feh - ($ - $$) db 0
			dw 0aa55h

