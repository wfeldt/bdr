		bits 16

		%include "bdr.inc"

		section .text

		org 0x24

		mov ax,hello


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

hello		db "Hi there", 13, 10, 0

