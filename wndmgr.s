wnd_description equ 0x00
wnd_l           equ 0x02
wnd_r           equ 0x04
wnd_t           equ 0x06
wnd_b           equ 0x08
wnd_sz          equ 0x10

wndmgr_setup:
	call	dll_alloc
	jc	out_of_memory_error
	mov	[window_list],ax

	ret

wndmgr_event_loop:
	xor	ax,ax ; since apps iret to here after callback
	mov	ds,ax

	.wait:
	hlt
	.loop:
	mov	ax,[cursor_x]
	mov	bx,[cursor_y]
	cmp	ax,[cursor_drawn_x]
	jne	.cursor_moved
	cmp	bx,[cursor_drawn_y]
	jne	.cursor_moved
	jmp	.wait

	.cursor_moved:
	cli ; this needs to be fast!
	call	gfx_restore_beneath_cursor
	mov	ax,[cursor_x]
	mov	bx,[cursor_y]
	mov	[cursor_drawn_x],ax
	mov	[cursor_drawn_y],bx
	call	gfx_draw_cursor
	sti
	jmp	.loop

wndmgr_move_cursor: ; input: ax = dx, dx = dy, ds = 0; preserves: everything; can run in interrupts
	push	ax
	push	dx
	add	[cursor_x],ax
	add	[cursor_y],dx
	mov	ax,[gfx_width]
	dec	ax
	xor	dx,dx
	cmp	[cursor_x],ax
	jle	.c0
	mov	[cursor_x],ax
	.c0:
	cmp	[cursor_x],dx
	jge	.c1
	mov	[cursor_x],dx
	.c1:
	mov	ax,[gfx_height]
	dec	ax
	xor	dx,dx
	cmp	[cursor_y],ax
	jle	.c2
	mov	[cursor_y],ax
	.c2:
	cmp	[cursor_y],dx
	jge	.c3
	mov	[cursor_y],dx
	.c3:
	pop	dx
	pop	ax
	ret

wndmgr_repaint: ; input: ds = 0; preserves: everything
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es

	mov	word [.wndrect + rect_l],0
	mov	ax,[gfx_width]
	mov	[.wndrect + rect_r],ax
	mov	word [.wndrect + rect_t],0
	mov	ax,[gfx_height]
	mov	[.wndrect + rect_b],ax
	mov	di,.wndrect
	mov	cl,3
	mov	bx,sys_draw_block
	int	0x20

	mov	ax,[window_list]
	.window_loop:
	call	dll_next
	call	dll_is_list
	jc	.window_loop_end
	mov	es,ax
	push	ax

	.draw_window:

	mov	ax,[es:wnd_l]
	mov	[.wndrect + rect_l],ax
	mov	ax,[es:wnd_r]
	mov	[.wndrect + rect_r],ax
	mov	ax,[es:wnd_t]
	mov	[.wndrect + rect_t],ax
	mov	ax,[es:wnd_b]
	mov	[.wndrect + rect_b],ax

	mov	di,.wndrect
	mov	bx,sys_draw_block
	mov	cl,7
	int	0x20
	mov	bx,sys_draw_frame
	mov	cx,frame_window
	int	0x20

	mov	ax,[es:wnd_description]
	mov	es,ax
	xor	si,si

	.draw_window_item:
	mov	al,[es:si + wnd_item_code]
	or	al,al
	jz	.next_window
	mov	bx,[es:si + wnd_item_l]
	add	bx,[.wndrect + rect_l]
	mov	[.itemrect + rect_l],bx
	mov	bx,[es:si + wnd_item_r]
	add	bx,[.wndrect + rect_l]
	mov	[.itemrect + rect_r],bx
	mov	bx,[es:si + wnd_item_t]
	add	bx,[.wndrect + rect_t]
	mov	[.itemrect + rect_t],bx
	mov	bx,[es:si + wnd_item_b]
	add	bx,[.wndrect + rect_t]
	mov	[.itemrect + rect_b],bx
	mov	di,.itemrect
	dec	al
	jz	.draw_button
	dec	al
	jz	.draw_wndtitle
	jmp	exception_handler

	.draw_next_window_item:
	xor	ah,ah
	mov	al,[es:si + wnd_item_strlen]
	add	si,ax
	add	si,wnd_item_string
	jmp	.draw_window_item

	.draw_button: ; di = .itemrect
	mov	bx,sys_draw_frame
	mov	cx,frame_3d_out
	int	0x20
	xor	ax,ax
	call	.draw_text_centered
	jmp 	.draw_next_window_item

	.draw_wndtitle:
	mov	ax,[.wndrect + rect_r]
	sub	ax,[.wndrect + rect_l]
	add	[.itemrect + rect_r],ax
	mov	bx,sys_draw_block
	mov	cl,1
	int	0x20
	mov	ax,0xF01
	call	.draw_text_centered
	jmp 	.draw_next_window_item

	.draw_text_centered:
	mov	cx,[.itemrect + rect_l]
	add	cx,[.itemrect + rect_r]
	mov	dx,[.itemrect + rect_t]
	add	dx,[.itemrect + rect_b]
	push	ds
	push	es
	push	si
	mov	bx,es
	mov	ds,bx
	xor	bx,bx
	mov	es,bx
	add	si,wnd_item_string
	mov	bx,sys_measure_text
	int	0x20
	sub	cx,[es:.itemrect + rect_r]
	sub	cx,[es:.itemrect + rect_l]
	shr	cx,1
	inc	cx
	sub	dx,[es:.itemrect + rect_b]
	sub	dx,[es:.itemrect + rect_t]
	shr	dx,1
	mov	bx,sys_draw_text
	int	0x20
	pop	si
	pop	es
	pop	ds
	ret
 
	.next_window:
	pop	ax
	jmp	.window_loop
	.window_loop_end:

	.draw_cursor:
	call	gfx_draw_cursor

	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax

	ret

	.wndrect: dw 0,0,0,0
	.itemrect: dw 0,0,0,0

do_wnd_create:
	push	ax
	push	bx
	push	ds
	push	es
	xor	bx,bx
	mov	ds,bx
	mov	cx,ax
	mov	ax,wnd_sz / 16
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jz	.return
	mov	es,ax
	mov	[es:wnd_description],cx
	mov	word [es:wnd_l],20
	mov	word [es:wnd_r],220
	mov	word [es:wnd_t],20
	mov	word [es:wnd_b],220
	mov	bx,ax
	mov	ax,[window_list]
	call	dll_insert_end
	mov	ax,bx
	call	wndmgr_repaint
	.return:
	pop	es
	pop	ds
	pop	bx
	pop	ax
	iret

do_wndmgr_syscall:
	or	bl,bl
	jz	do_wnd_create
	jmp	exception_handler

window_list: dw 0
cursor_x: dw 50
cursor_y: dw 100
cursor_drawn_x: dw 50
cursor_drawn_y: dw 100
