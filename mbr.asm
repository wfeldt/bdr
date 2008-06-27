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
			mov dl,[edd.drive]
			mov ah,41h
			mov bx,55aah
			push dx
			int 13h
			pop dx
			jc disk_read_chs
			cmp bx,0aa55h
			jnz disk_read_chs
			test cl,1
			jz disk_read_chs
disk_read_edd:
			mov si,edd.packet
			mov ah,42h
			int 13h
			ret

disk_read_chs:
			or dword [edd.sector+4],0
			jnz disk_read_chs_80
			mov ah,8
			xor di,di
			int 13h
			jc disk_read_chs_90
			mov ax,cx
			shr al,6
			xchg al,ah
			and cx,3fh
			movzx bx,dh
			inc ax
			inc bx
			; bx = heads
			; cx = sectors
			; ax = cylinders
			mov bp,cx
			imul bp,bx
			jz disk_read_chs_80
			mul bp
			shl edx,16
			xchg ax,dx
			cmp [edd.sector],edx
			jae disk_read_chs_80
			mov ax,[edd.sector]
			mov dx,[edd.sector+2]
			div bp
			; ax = cylinder
			; dx = s/h
			shl ah,6
			xchg al,ah
			xchg ax,bx
			xchg ax,dx
			cwd
			div cx
			; ax = head
			; dx = sector
			inc dx
			or bx,dx
			mov cx,bx
			mov dh,al
			mov dl,[edd.drive]
			mov al,[edd.count]
			les bx,[edd.buf]
			mov ah,2
			int 13h
			jc disk_read_chs_90
			xor ax,ax
			mov es,ax
			ret
disk_read_chs_80:
			stc
disk_read_chs_90:
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

