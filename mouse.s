; Assuming a Microsoft serial mouse is connected to COM1.

mouse_setup:
	mov	ax,[0x400] ; COM1
	mov	[mouse_port],ax

	.disable_interrupts:
	mov	dx,[mouse_port]
	add	dx,1
	xor	al,al
	out	dx,al

	.set_baud_rate:
	mov	dx,[mouse_port]
	add	dx,3
	mov	al,0x80
	out	dx,al
	mov	dx,[mouse_port]
	add	dx,0
	mov	al,96 ; 1200 bps
	out	dx,al
	mov	dx,[mouse_port]
	add	dx,1
	mov	al,0x00
	out	dx,al

	.set_line_control:
	mov	dx,[mouse_port]
	add	dx,3
	mov	al,2 ; 7 data bits, 1 stop bit, no parity
	out	dx,al

	; TODO Keep writing this!

	ret

mouse_port: dw 0
