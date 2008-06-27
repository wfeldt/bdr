
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
bht.sizeof		equ 0x1e

bdr_magic.low		equ 0xcbe2c18e
bdr_magic.high		equ 0x9ef8cb23

