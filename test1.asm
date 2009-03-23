			bits 16

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

			mov si,msg_hello
			jmp final_msg

%if 0
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

%endif


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
			dd 0, 0

edd_checked		db 2

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
msg_nl			db 13, 10
msg_no_msg		db 0
msg_hello		db "starting test1", 13, 10, 0
msg_next		db 10, "Done.", 0

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
%if ($ - $$) > 1b8h
%error "test1 too big"
%endif

			times 1b8h - ($ - $$) db 0

