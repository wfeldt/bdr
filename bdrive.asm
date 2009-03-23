			bits 16

			%include "bdr.inc"

			section .text

			org bdr_load_start + sht.sizeof + bht.sizeof

			mov si,disk_buf
			mov di,bdr_load_start
			mov cx,100h
			rep movsw

			jmp bdr_load_start - disk_buf + main

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Read sector, check crc and copy to [prog_end].
;
; return:
;   ZF:			1 ok, 0 error
;
disk_read:
			mov bp,[mbr_dap]

			mov word [bp+edd.count],1
			mov si,bdr_load_start + sht.next
			lea di,[bp+edd.sector]
			movsd
			movsw
			xor ax,ax
			stosw			; only 48 bit
			call [mbr_disk_read]
			sbb cx,cx
			jnz disk_read_90

			mov si,disk_buf+sht.id
			mov di,bdr_load_start+sht.id
			mov cl,4		; cx was 0
			rep cmpsw
			jnz disk_read_50
			xor dx,dx
			mov ch,1		; cx was 0
			mov si,disk_buf
disk_read_50:
			lodsw
			add dx,ax
			loop disk_read_50
			jnz disk_read_90
			mov si,disk_buf + sht.next
			mov di,bdr_load_start + sht.next
			movsd
			movsd
%if sht.next+8 != sht.sizeof
			mov si,disk_buf + sht.sizeof
%endif
			mov di,[prog_end]
			mov cx,(200h-sht.sizeof)/2
			rep movsw
			mov [prog_end],di
			; ZF = 1
disk_read_90:
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
; Read remaining code.
;
; return:
;   ZF:			1 ok, 0 error
;
read_code:
			dec word [bdr_load_start+sht.sizeof+bht.bdr_size]
			jz read_code_90
			inc dword [bdr_load_start+sht.id]
			call disk_read
			jz read_code
read_code_90:
some_ret_instr:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Variables that need to be in the first sector.
;
hello			db "bdrive 0.3", 13, 10, 0

mbr_disk_read		dw 0
mbr_dap			dw 0
prog_end		dw bdr_load_start+200h

new_int13		equ 0
			%include "bdrive_struc.inc"


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
main:
			; bp = device address packet
			; bx = mbr disk read function address

			mov [mbr_disk_read],bx
			mov [mbr_dap],bp

			mov al,[bp+edd.drive]
			mov [bdr_load_start + sht.sizeof + bht.drive_map],al

			mov si,hello
			call print

			call read_code
			jnz some_ret_instr	; main_90 might be outside first sector

bdrive_first_sector_end:

%if ($ - $$) > 200h
%error "bdrive: first sector code too big"
%endif

			mov si,code_ok
			call print

			call read_map
			jnz main_90

			mov si,map_ok
			call print

			call get_drive_config

			mov si,drive_nr
			call print
			mov al,[bdrive.drive]
			call hex2
			mov si,msg_nl
			call print

			call setup_bdrive

			mov si,txt_drive_active
			call print

%if 0
			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

			stc
			mov dl,[bdrive.drive]
			mov ah,8
			int 13h

			stc
			mov dl,[bdrive.drive]
			mov ah,41h
			mov bx,55aah
			int 13h

			stc
			mov dl,[bdrive.drive]
			mov ah,48h
			mov si,foo1
			int 13h

			jmp xxx

foo1:			dw 26
			times 30 db 7

xxx:


			;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
%endif

			call load_mbr

			mov si,msg_no_mbr
			call print

			jnz main_90

main_90:
			ret

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Read mapping data.
;
; return:
;   ZF:			1 ok, 0 error
;
read_map:
			mov ax,[413h]
			mov [bdrive.low_mem],ax
			mov bx,[bdr_load_start+sht.sizeof+bht.map_size]
			inc bx
			shr bx,1
			sub ax,bx
			shl ax,6
			mov [bdrive.map_seg],ax
			movzx ebx,ax
			shl ebx,4

read_map_40:
			inc dword [bdr_load_start+sht.id]
			mov si,[prog_end]
			push si
			push ebx
			call disk_read
			pop ebx
			pop si
			jnz read_map_90
			push es
			mov [prog_end],si
			mov edx,ebx
			shr edx,4
			mov es,dx
			mov di,bx
			and di,0fh
			mov cx,(200h-sht.sizeof)/2
			rep movsw
			pop es
			add ebx,200h-sht.sizeof
			dec word [bdr_load_start+sht.sizeof+bht.map_size]
			jnz read_map_40
read_map_90:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Get emulated bios drive number.
;
get_drive_config:
			mov ax,[bdr_load_start+sht.sizeof+bht.bios_drive]
			test ah,80h
			jnz get_drive_config_30
			mov [bdrive.drive],al
			jmp get_drive_config_90
get_drive_config_30:
			mov ah,8
			mov dl,80h
			xor di,di
			push ax
			int 13h
			pop ax
			jnc get_drive_config_40
			mov dl,0
get_drive_config_40:
			mov [bdrive.drives],dl
			add dl,80h
			add al,dl
			mov [bdrive.drive],al
get_drive_config_90:
			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Setup resident part and connect to int 13h.
;
setup_bdrive:
			mov eax,[13h*4]
			mov [bdrive.old_int13],eax

			mov ax,[bdrive_res_start+bdrive.new_int13-bdrive]
			mov [bdrive.new_int13],ax

			mov ax,[bdrive.map_seg]
			sub ax,(bdrive_res_end-bdrive_res_start+0x0f)>>4
			mov [bdrive.new_int13+2],ax

			; copy parameter block
			mov si,bdrive
			mov di,bdrive_res_start
			mov cx,bdrive.size
			rep movsb

			; copy bht
			mov si,bdr_load_start+sht.sizeof
			mov cx,bht.sizeof
			rep movsb

			; copy resident part
			mov si,bdrive_res_start
			xor di,di
			mov cx,bdrive_res_end-bdrive_res_start
			push es
			mov es,ax
			rep movsb
			pop es

			; adjust low mem size
			mov ax,[bdrive.new_int13+2]
			shr ax,6
			mov [413h],ax

			; activate new int 13h
			mov eax,[bdrive.new_int13]
			mov [13h*4],eax

			ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Load (and start) new MBR.
;
; return:
;  Does not return if ok.
;
load_mbr:
			mov si,[mbr_dap]
			mov word [si+edd.count],1
			xor eax,eax
			lea di,[si+edd.sector]
			stosd
			stosd
			mov dl,[bdrive.drive]
			mov ah,42h
			int 13h

			sbb cx,cx
			jnz load_mbr_90

			mov si,disk_buf
			mov di,mbr_start

			cmp word [si+0x1fe],0aa55h
			jnz load_mbr_90

			cmp byte [si],0
			jz load_mbr_90

			mov cx,100h
			rep movsw

			mov dl,[bdrive.drive]
			xor sp,sp

			jmp 0:07c00h

load_mbr_90:
			ret


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

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

code_ok			db "code loaded"
msg_nl			db 10, 0
map_ok			db "map loaded", 10, 0
txt_drive_active	db "booting drive", 10, 0
msg_no_mbr		db "Error: drive not bootable.", 10, 0

drive_nr		db 'adding drive 0x'
hex1_buf		db 0, 0

bdrive_res_start:
			%include "bdrive_res.hex"
bdrive_res_end:

