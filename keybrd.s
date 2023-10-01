keybrd_setup:
	.setup_isr:
	cli
	mov	word [9 * 4 + 0],keybrd_isr
	mov	word [9 * 4 + 2],0
	sti

	ret

keybrd_isr:
	cld
	push	ax
	push	dx
	push	ds

	xor	ax,ax
	mov	ds,ax

	.read_scancode:
	in	al,0x60
	mov	ah,al
	and	ax,0x807F
	call	wndmgr_press_key

	.reset_control:
	in	al,0x61
	or	al,0x80
	out	0x61,al
	and	al,0x7F
	out	0x61,al

	.set_eoi:
	mov	dx,0x20 ; pic1 command
	mov	al,0x20 ; eoi
	out	dx,al

	pop	ds
	pop	dx
	pop	ax

	iret
