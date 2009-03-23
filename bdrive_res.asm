                        bits 16

                        section .text  

			%include "bdr.inc"

pa_edi			equ 0
pa_esi			equ 4
pa_ebp			equ 8
pa_esp			equ 12
pa_ebx			equ 16
pa_edx			equ 20
pa_ecx			equ 24
pa_eax			equ 28
pa_ds			equ 32
pa_es			equ 34

			; must be first
			%include "bdrive_struc.inc"
			; must follow bdrive_struc.inc
bht			times bht.sizeof db 0

jt_basic		dw f_00, f_01, f_02, f_03, f_04, f_05, f_06, f_07
			dw f_08, f_09,    0,    0, f_0c, f_0d
jt_edd			dw       f_41, f_42, f_43, f_44, f_45, f_46, f_47
			dw f_48, f_49

int13_err		db 0
int13_err_last		db 0

edd			dw 10h		; edd.packet
edd_count		dw 0
edd_buf			dd 0
edd_mapped_sector	dd 0,0

edd_real_sector		dd 0,0
edd_mapped_count	dw 0
edd_real_count		dw 0
edd_mapped_drive	db 0
edd_buf_lin		dd 0

new_int13:
			cmp dl,[cs:bdrive.drive]
			jz new_int13_10
			jmp far [cs:bdrive.old_int13]
new_int13_10:
			push es
			push ds
			pushad
			mov bp,sp

			push cs
			pop ds

			push ax
			mov al,[int13_err]
			mov [int13_err_last],al
			pop ax
			mov byte [int13_err],1

			cmp ah,0dh
			jbe new_int13_20

			test word [bht+bht.flags],1
			jz new_int13_80

			cmp ah,41h
			jb new_int13_80
			cmp ah,49h
			ja new_int13_80
			sub ah,41h
			movzx di,ah
			add di,di
			mov bx,[jt_edd+di]
			jmp new_int13_30
new_int13_20:
			movzx di,ah
			add di,di
			mov bx,[jt_basic+di]
new_int13_30:
			or bx,bx
			jz new_int13_80
			call bx
			jmp new_int13_90

new_int13_80:
			stc
			mov ah,[int13_err]
			mov [bp+pa_eax+1],ah
new_int13_90:
			popad
			pop ds
			pop es
			push ax
			lahf
			mov [esp+6],ah
			pop ax
			iret


f_00:			; recalibrate
f_04:			; verify
f_05:			; format floppy
f_06:			; format disk
f_07:			; format disk
f_09:			; set drive params
f_0c:			; seek
f_0d:			; reset
f_44:			; edd verify
f_46:			; edd eject
f_47:			; edd seek
f_49:			; edd media change
			xor ah,ah
			mov byte [int13_err],ah
			ret


f_01:			; last status
			mov ah,[int13_err_last]
			mov byte [int13_err],0
			cmp ah,1
			cmc
			ret


f_02:			; read

			ret


f_03:			; write
			ret


f_08:			; drive params
			mov cx,[bht+bht.disk_geo_cylinders]
			dec cx
			xchg ch,cl
			shl cl,6
			or cl,[bht+bht.disk_geo_sectors]
			mov dh,[bht+bht.disk_geo_heads]
			dec dh
			mov dl,[bdrive.drives]
			mov al,[bdrive.drive]
			sub al,dl
			cmp al,80h
			jnz f_08_80
			inc dl		; if there's no gap, increase
f_08_80:
			mov [bp+pa_ecx],cx
			mov [bp+pa_edx],dx
			xor ax,ax
			mov [bp+pa_eax],ax
			mov [int13_err],ah
			ret


f_41:			; edd install check
			mov word [bp+pa_ebx],0aa55h
			mov word [bp+pa_eax],3000h
			mov word [bp+pa_ecx],1
			clc
			ret


f_42:			; edd read

			mov es,[bp+pa_ds]

			xor ax,ax
			mov [bp+pa_eax+1],ah
			mov [int13_err],ah

			mov ax,[es:si+edd.count]
			mov [edd_real_count],ax
			or ax,ax
			jz f_42_90

			movzx eax,word [es:si+edd.buf]
			movzx edx,word [es:si+edd.buf+2]
			shl edx,4
			add eax,edx
			mov [edd_buf_lin],eax

			mov eax,[es:si+edd.sector]
			mov [edd_real_sector],eax
			mov eax,[es:si+edd.sector+4]
			mov [edd_real_sector+4],eax

f_42_20:
			call map_sector

			mov ax,[edd_mapped_count]
			or ax,ax
			jz f_42_80

			mov dx,[edd_real_count]
			cmp ax,dx
			jbe f_42_40
			xchg ax,dx
f_42_40:
			movzx edx,ax
			mov [edd_count],ax

			mov eax,[edd_buf_lin]
			mov ebx,eax
			shr eax,4
			shl eax,16
			mov ax,bx
			and ax,0fh
			mov [edd_buf],eax

			sub [edd_real_count],dx
			add [edd_real_sector],edx
			adc dword [edd_real_sector+4],0

			shl edx,9
			add [edd_buf_lin],edx

			push ds

			mov ah,42h
			mov si,edd
			mov dl,[edd_mapped_drive]
			pushf
			call far [bdrive.old_int13]

			pop ds

			jc f_42_80

			cmp word [edd_real_count],0
			jnz f_42_20

			jmp f_42_90

f_42_80:
			mov byte [bp+pa_eax+1],4
			mov byte [int13_err],4
			stc
f_42_90:
			ret


f_43:			; edd write
			ret


f_45:			; edd lock/unlock
			mov word [bp+pa_eax],0
			clc
			ret


f_48:			; edd drive params
			mov es,[bp+pa_ds]
			mov ax,[es:si]
			cmp ax,1ah
			jb f_48_70
			mov word [es:si],1ah
			mov word [es:si+2],0bh
			mov word [es:si+18h],200h
			movzx ecx,byte [bht+bht.disk_geo_heads]
			mov [es:si+8],ecx
			movzx ebx,byte [bht+bht.disk_geo_sectors]
			mov [es:si+0ch],ebx
			mov eax,[bht+bht.disk_size]
			mov [es:si+10h],eax
			mov edx,[bht+bht.disk_size+4]
			mov [es:si+14h],edx
			imul ecx,ebx
			div ecx
			mov [es:si+4],eax

			xor ah,ah
			jmp f_48_80

f_48_70:
			mov ah,1
			stc
f_48_80:
			mov [bp+pa_eax+1],ah
			mov [int13_err],ah
f_48_90:
			ret


;
; map edd_real_sector to edd_mapped_sector & edd_mapped_drive
; edd_mapped_count = 0 -> mapping failed
;
map_sector:
			push es
			mov es,[bdrive.map_seg]
			mov cx,[bht+bht.map_entries]

			xor bp,bp

			xor eax,eax

			mov [edd_mapped_count],ax

			mov edx,[edd_real_sector]

map_sector_20:
			mov edi,edx
			mov ebx,[es:bp+4]
			shr ebx,16
			and ebx,(1 << 12) - 1
			sub edx,ebx
			jb map_sector_60

			add bp,8
			jnz map_sector_40
			mov bx,es
			add bx,1000h
			mov es,bx
map_sector_40:
			dec cx
			jnz map_sector_20
			jmp map_sector_90

map_sector_60:
			neg edx
			mov [edd_mapped_count],dx
			mov eax,[es:bp]
			mov edx,[es:bp+4]
			mov ebx,edx
			and edx,(1 << 16) - 1
			add eax,edi
			adc edx,0
			mov [edd_mapped_sector],eax
			mov [edd_mapped_sector+4],edx
			shr ebx,28
			mov al,[bx+bht+bht.drive_map]
			mov [edd_mapped_drive],al

map_sector_90:
			pop es
			ret


%if 0
			pushf
			call far [cs:bdrive.old_int13]
			push ax
			lahf
			mov [esp+6],ah
			pop ax
			iret

%endif


