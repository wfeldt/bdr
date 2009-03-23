
; sector_head_t
sht.id			equ 0x00
sht.next		equ 0x08
sht.sizeof		equ 0x10


; bdr_head_t
bht.magic		equ 0x00
bht.drive_map		equ 0x08
bht.bdr_size		equ 0x18
bht.map_size		equ 0x1a
bht.map_entries		equ 0x1c
bht.bios_drive		equ 0x1e
bht.disk_size		equ 0x20
bht.disk_geo_cylinders	equ 0x28
bht.disk_geo_heads	equ 0x2a
bht.disk_geo_sectors	equ 0x2b
bht.flags		equ 0x2c
bht.sizeof		equ 0x2e

bdr_magic.low		equ 0xcbe2c18e
bdr_magic.high		equ 0x9ef8cb23

disk_buf		equ 7000h
mbr_vars_start		equ 7b80h
mbr_start		equ 7c00h
bdr_load_start		equ 8000h

struc mbr_vars
edd.packet		resw 1
edd.count		resw 1
edd.buf			resw 2
edd.sector		resd 2
edd.drive		resb 1
bios_drives		resb 1
endstruc

%macro x86emu_print 1
			db 67h
			jmp %%foo
			db 1
			db %1
%%foo:
%endmacro

%macro x86emu_trace_on 1
			db 67h
			jmp %%foo
			db 2
			dd %1
%%foo:
%endmacro

%macro x86emu_trace_off 1
			db 67h
			jmp %%foo
			db 3
			dd %1
%%foo:
%endmacro

%macro x86emu_dump 1
			db 67h
			jmp %%foo
			db 4
			dd %1
%%foo:
%endmacro

%macro x86emu_reset_stats 0
			db 67h
			jmp %%foo
			db 5
%%foo:
%endmacro

x86emu_trace_regs	equ 1 << 0
x86emu_trace_code	equ 1 << 1
x86emu_trace_data	equ 1 << 2
x86emu_trace_acc	equ 1 << 3
x86emu_trace_io		equ 1 << 4
x86emu_trace_ints	equ 1 << 5
x86emu_trace_time	equ 1 << 6
x86emu_trace_debug	equ 1 << 7
x86emu_trace_default	equ x86emu_trace_regs | x86emu_trace_code | x86emu_trace_data | x86emu_trace_io | x86emu_trace_ints

x86emu_dump_regs	equ 1 << 0
x86emu_dump_mem		equ 1 << 1
x86emu_dump_acc_mem	equ 1 << 2
x86emu_dump_inv_mem	equ 1 << 3
x86emu_dump_attr	equ 1 << 4
x86emu_dump_ascii	equ 1 << 5
x86emu_dump_io		equ 1 << 6
x86emu_dump_ints	equ 1 << 7
x86emu_dump_time	equ 1 << 8
x86emu_dump_mem_default	equ x86emu_dump_acc_mem | x86emu_dump_attr | x86emu_dump_ascii

