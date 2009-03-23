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

