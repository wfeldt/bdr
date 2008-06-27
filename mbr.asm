			bits 16

			%include "bdr.inc"

disk_buf		equ 8000h

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

			call check

			mov si,msg_not_found
			jc main_20
			mov si,msg_ok
main_20:
			call print

			jmp $


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
check:
			mov word [edd.count],1
			mov eax,[start_sector]
			mov [edd.sector],eax
			mov ax,[start_sector+4]
			mov [edd.sector+4],ax
			call disk_read
			jc check_90
			mov eax,[disk_buf+sht.id]
			mov edx,[disk_buf+sht.id+4]
			xor eax,[id]
			xor edx,[id+4]
			or eax,edx
			jz check_90
			stc
check_90:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
disk_read:
			mov ah,41h
			mov bx,55aah
			call int_13
			jc disk_read_chs
			cmp bx,0aa55h
			jnz disk_read_chs
			test cl,1
			jz disk_read_chs
disk_read_edd:
			mov si,edd.packet
			mov ah,42h
			jmp int_13

disk_read_chs:
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
			xchg ax,bp
			mov ax,[edd.sector]
			mov dx,[edd.sector + 2]
			cmp dx,bp
			jae disk_read_edd
			div bp
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
int_13:
			mov dl,[edd.drive]
			int 13h
			ret

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

msg_ok			db "ok", 13, 10, 0
msg_not_found		db "not found", 13, 10, 0

edd.drive		db 0
edd.packet		db 10h, 0
edd.count		dw 1
edd.buf			dw 0, disk_buf >> 4
edd.sector		dd 0,0

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

%if ($ - $$) > 1a8h
%error "mbr too big"
%endif

			times 1a8h - ($ - $$) db 0
start_sector		dd 0, 0
id			dd 0, 0

			times 1feh - ($ - $$) db 0
			dw 0aa55h

