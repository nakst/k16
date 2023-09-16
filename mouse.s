; Assuming a Microsoft serial mouse is connected to COM1.

%macro mouse_write 2 ; port, data byte
	mov	dx,[mouse_port]
	add	dx,%1
	mov	al,%2
	out	dx,al
%endmacro

mouse_setup:
	mov	ax,[0x400] ; COM1
	mov	[mouse_port],ax

	mouse_write 1,0x00 ; disable interrupts
	mouse_write 3,0x80 ; latch baud rate
	mouse_write 0,0x60 ; baud rate = 1200 bps
	mouse_write 1,0x00 ; high bits for baud rate divisor
	mouse_write 3,0x42 ; 7 data bits, 1 stop bit, no parity, break line
	mouse_write 2,0xC7 ; enable and clear 14-byte fifo
	mouse_write 4,0x00 ; clear RTS and DTR

	mov	bx,[0x46C]
	.reset_wait_loop:
	mov	dx,[0x46C]
	sub	dx,bx
	cmp	dx,2
	jb	.reset_wait_loop

	mouse_write 4,0x0B ; set RTS and DTR; enable IRQs
	
	mov	bx,[0x46C]
	mov	dx,[mouse_port]
	add	dx,5
	.wait_data:
	mov	cx,[0x46C]
	sub	cx,bx
	cmp	cx,5
	ja	.no_mouse
	in	al,dx
	test	al,0x01
	jz	.wait_data
	mov	dx,[mouse_port]
	in	al,dx
	cmp	al,'M'
	jne	.wait_data

	.setup_isr:
	cli
	mov	word [12 * 4 + 0],mouse_isr
	mov	word [12 * 4 + 2],0
	mov	dx,0x21 ; pic1 data
	in	al,dx
	and	al,~(1 << 4)
	out	dx,al ; unmask
	mouse_write 1,0x01 ; enable interrupts
	sti

	.no_mouse:
	ret

mouse_isr:
	push	ax
	push	dx
	push	ds
	xor	ax,ax
	mov	ds,ax
	.read_loop:
	mov	dx,[mouse_port]
	add	dx,5
	in	al,dx
	test	al,0x01
	jz	.no_data
	mov	dx,[mouse_port]
	in	al,dx

	test	al,0x40
	jz	.x_or_y
	mov	byte [mouse_read_index],1
	jmp	.dbuttons

	.x_or_y:
	inc	byte [mouse_read_index]
	cmp	byte [mouse_read_index],2
	je	.dx
	cmp	byte [mouse_read_index],3
	je	.dy
	jmp	.read_loop

	.dbuttons:
	mov	[mouse_lead_byte],al
	mov	byte [mouse_left],0
	mov	byte [mouse_right],0
	test	al,0x20
	jz	.no_left
	mov	byte [mouse_left],1
	.no_left:
	test	al,0x10
	jz	.no_right
	mov	byte [mouse_right],1
	.no_right:
	jmp	.read_loop

	.dx:
	mov	ah,[mouse_lead_byte]
	shl	ah,1
	shl	ah,1
	shl	ah,1
	shl	ah,1
	shl	ah,1
	shl	ah,1
	or	al,ah
	cbw
	xor	dx,dx
	call	wndmgr_move_cursor
	jmp	.read_loop

	.dy:
	mov	ah,[mouse_lead_byte]
	shl	ah,1
	shl	ah,1
	shl	ah,1
	shl	ah,1
	and	ah,0xC0
	or	al,ah
	cbw
	mov	dx,ax
	xor	ax,ax
	call	wndmgr_move_cursor
	jmp	.read_loop
	
	.no_data:
	mov	dx,0x20 ; pic1 command
	mov	al,0x20 ; eoi
	out	dx,al
	pop	ds
	pop	dx
	pop	ax
	iret

mouse_port: dw 0
mouse_left: db 0
mouse_right: db 0
mouse_read_index: db 0
mouse_lead_byte: db 0
