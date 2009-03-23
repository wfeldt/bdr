			%include "x86emu.inc"

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

