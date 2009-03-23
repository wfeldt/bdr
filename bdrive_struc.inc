bdrive:
bdrive.map_seg		dw 0
bdrive.low_mem		dw 0
bdrive.drives		db 0
bdrive.drive		db 0
bdrive.drive_map	times 16 db 0
bdrive.old_int13	dw 0, 0
bdrive.new_int13	dw new_int13, 0
bdrive.size		equ $-bdrive
