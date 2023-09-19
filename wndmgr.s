; TODO Clipping during wndmgr_repaint_item.
; TODO Make a copy of the window description.
; TODO Moving and resizing windows.
; TODO Removing button push flag when mouse not within bounds.

wnd_description equ 0x00
wnd_l           equ 0x02
wnd_r           equ 0x04
wnd_t           equ 0x06
wnd_b           equ 0x08
wnd_segment     equ 0x0A
wnd_sz          equ 0x10

input_event_type equ 0x00
input_event_data equ 0x01
input_event_cx   equ 0x02
input_event_cy   equ 0x04
input_event_sz   equ 0x06

input_event_type_left_down  equ 0x01
input_event_type_right_down equ 0x02
input_event_type_left_up    equ 0x03
input_event_type_right_up   equ 0x04

input_event_queue_count equ 8 ; TODO Is this long enough?

wnd_client_off_x equ 4
wnd_client_off_y equ 24

wndmgr_send_callback: ; input: ax = window, es:bx = item, cx = message code, dx = message data 1, si = message data 2, di = message data 3, ds = 0; preserves: everything
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	push	es

	pushf
	push	ds
	mov	bp,.return
	push	bp
	mov	bp,ax

	pushf
	mov	es,ax
	mov	ax,[es:wnd_segment]
	mov	ds,ax
	push	ax
	mov	ax,[es:wnd_description]
	mov	es,ax
	mov	ax,[es:wnd_desc_callback]
	push	ax

	mov	ax,bp
	iret

	.return:
	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret

class_button:
	.on_left_down: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	or	word [es:bx + wnd_item_flags],wnd_item_flag_pushed
	call	wndmgr_repaint_item
	jmp	wndmgr_process_input_event.after_left_down

	.on_left_up: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	test	word [es:bx + wnd_item_flags],wnd_item_flag_pushed
	jz	.sent_click
	and	word [es:bx + wnd_item_flags],~wnd_item_flag_pushed
	push	bx
	push	ax
	call	wndmgr_repaint_item
	pop	ax
	pop	bx
	mov	cx,msg_clicked
	mov	dx,[es:bx + wnd_item_id]
	call	wndmgr_send_callback
	.sent_click:
	jmp	wndmgr_process_input_event.after_left_up

	.on_draw: ; input: ds = 0, es:si = item, di = .itemrect, ds = 0; preserves: ds, es, si, bp
	mov	bx,sys_draw_frame
	mov	cx,frame_3d_out
	test	word [es:si + wnd_item_flags],wnd_item_flag_pushed
	jz	.not_pushed
	mov	cx,frame_3d_in
	.not_pushed:
	int	0x20
	test	word [es:si + wnd_item_flags],wnd_item_flag_pushed
	jz	.not_pushed2
	inc	word [di + rect_l]
	inc	word [di + rect_r]
	inc	word [di + rect_t]
	inc	word [di + rect_b]
	.not_pushed2:
	xor	ax,ax
	jmp	wndmgr_repaint.draw_text_centered

class_wndtitle:
	.on_draw:
	mov	bx,sys_draw_block
	mov	cl,1
	int	0x20
	mov	ax,0xF01
	jmp	wndmgr_repaint.draw_text_centered

class_static:
	.on_draw:
	push	si
	xor	ax,ax
	mov	cx,[di + rect_l]
	mov	dx,[di + rect_t]
	add	dx,[def_font]
	add	si,wnd_item_string
	mov	bx,es
	push	ds
	mov	ds,bx
	mov	bx,sys_draw_text
	int	0x20
	pop	ds
	pop	si
	ret

class_custom:
	.on_left_down: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	mov	cx,msg_custom_mouse
	mov	dx,[es:bx + wnd_item_id]
	mov	si,1
	call	wndmgr_send_callback
	jmp	wndmgr_process_input_event.after_left_down

	.on_left_up: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	mov	cx,msg_custom_mouse
	mov	dx,[es:bx + wnd_item_id]
	xor	si,si
	call	wndmgr_send_callback
	jmp	wndmgr_process_input_event.after_left_up

	.on_right_down: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	mov	cx,msg_custom_mouse
	mov	dx,[es:bx + wnd_item_id]
	mov	si,3
	call	wndmgr_send_callback
	jmp	wndmgr_process_input_event.after_left_down

	.on_right_up: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	mov	cx,msg_custom_mouse
	mov	dx,[es:bx + wnd_item_id]
	mov	si,2
	call	wndmgr_send_callback
	jmp	wndmgr_process_input_event.after_left_up

	.on_draw:
	push	si
	mov	ax,cx
	mov	bx,si
	mov	cx,msg_custom_draw
	mov	dx,[es:bx + wnd_item_id]
	mov	si,ds
	call	wndmgr_send_callback
	pop	si
	ret

wndmgr_setup:
	call	dll_alloc
	jc	out_of_memory_error
	mov	[window_list],ax

	mov	cx,input_event_queue_count
	mov	si,input_event_queue
	.clear_queue:
	mov	byte [si + input_event_type],0
	add	si,input_event_sz
	loop	.clear_queue

	mov	bx,1
	call	wndmgr_repaint

;	mov	bx,100
;	mov	[cursor_x],bx
;	mov	bx,180
;	mov	[cursor_y],bx
;	mov	bx,input_event_type_left_down
;	call	wndmgr_push_input_event
;	mov	bx,input_event_type_left_up
;	call	wndmgr_push_input_event

	ret

wndmgr_event_loop:
	xor	ax,ax ; since apps iret to here after callback
	mov	ds,ax

	.wait:
	hlt
	.loop:
	call	wndmgr_process_input_event
	.no_input_event:
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

wndmgr_process_input_event: ; input: ds = 0; trashes: all except ds
	cli
	cmp	byte [input_event_queue + input_event_type],0
	jz	.no_event

	.has_event:
	mov	ax,[input_event_queue + input_event_type]
	push	ax
	mov	ax,[input_event_queue + input_event_cx]
	push	ax
	mov	ax,[input_event_queue + input_event_cy]
	push	ax

	.pop:
	xor	ax,ax
	mov	es,ax
	mov	cx,(input_event_queue_count - 1) * input_event_sz
	mov	si,input_event_sz
	mov	di,input_event_queue
	add	si,di
	rep	movsb

	pop	ax
	mov	[cursor_y_sync],ax
	pop	ax
	mov	[cursor_x_sync],ax
	pop	ax

	.process:
	sti
	cmp	al,input_event_type_left_down
	je	.on_left_down
	cmp	al,input_event_type_left_up
	je	.on_left_up
	cmp	al,input_event_type_right_down
	je	.on_right_down
	cmp	al,input_event_type_right_up
	je	.on_right_up
	jmp	exception_handler

	.no_event:
	sti
	ret

	.on_left_down:
	call	.find_item_under_cursor
	mov	bx,[hot_item]
	or	bx,bx
	jz	.no_event
	mov	ax,[hot_window]
	mov	es,ax
	mov	cx,[es:wnd_description]
	mov	es,cx
	mov	cl,[es:bx + wnd_item_code]
	cmp	cl,wnd_item_code_button
	je	class_button.on_left_down
	cmp	cl,wnd_item_code_custom
	je	class_custom.on_left_down
	.after_left_down:
	ret

	.on_left_up:
	mov	bx,[hot_item]
	or	bx,bx
	jz	.no_event
	mov	ax,[hot_window]
	mov	es,ax
	mov	cx,[es:wnd_description]
	mov	es,cx
	mov	cl,[es:bx + wnd_item_code]
	cmp	cl,wnd_item_code_button
	je	class_button.on_left_up
	cmp	cl,wnd_item_code_custom
	je	class_custom.on_left_up
	.after_left_up:
	ret

	.on_right_down:
	call	.find_item_under_cursor
	mov	bx,[hot_item]
	or	bx,bx
	jz	.no_event
	mov	ax,[hot_window]
	mov	es,ax
	mov	cx,[es:wnd_description]
	mov	es,cx
	mov	cl,[es:bx + wnd_item_code]
	cmp	cl,wnd_item_code_custom
	je	class_custom.on_right_down
	.after_right_down:
	ret

	.on_right_up:
	mov	bx,[hot_item]
	or	bx,bx
	jz	.no_event
	mov	ax,[hot_window]
	mov	es,ax
	mov	cx,[es:wnd_description]
	mov	es,cx
	mov	cl,[es:bx + wnd_item_code]
	cmp	cl,wnd_item_code_custom
	je	class_custom.on_right_up
	.after_right_up:
	ret

	.find_item_under_cursor:
	mov	ax,[window_list]
	.find_item_under_cursor_window_loop:
	call	dll_prev
	call	dll_is_list
	jc	.find_item_under_cursor_window_loop_end
	mov	es,ax
	mov	cx,[es:wnd_l]
	mov	dx,[es:wnd_t]
	mov	bx,[cursor_x_sync]
	cmp	bx,cx
	jl	.find_item_under_cursor_window_loop
	cmp	bx,[es:wnd_r]
	jge	.find_item_under_cursor_window_loop
	mov	bx,[cursor_y_sync]
	cmp	bx,dx
	jl	.find_item_under_cursor_window_loop
	cmp	bx,[es:wnd_b]
	jge	.find_item_under_cursor_window_loop
	mov	[hot_window],ax
	mov	ax,[es:wnd_description]
	mov	es,ax
	mov	si,wnd_desc_sz
	.find_item_under_cursor_item_loop:
	mov	al,[es:si + wnd_item_code]
	or	al,al
	jz	.find_item_under_cursor_item_loop_end
	mov	bx,[cursor_x_sync]
	sub	bx,cx
	cmp	bx,[es:si + wnd_item_l]
	jl	.find_item_under_cursor_item_loop_next
	cmp	bx,[es:si + wnd_item_r]
	jge	.find_item_under_cursor_item_loop_next
	mov	bx,[cursor_y_sync]
	sub	bx,dx
	cmp	bx,[es:si + wnd_item_t]
	jl	.find_item_under_cursor_item_loop_next
	cmp	bx,[es:si + wnd_item_b]
	jge	.find_item_under_cursor_item_loop_next
	mov	[hot_item],si
	ret
	.find_item_under_cursor_item_loop_next:
	xor	ah,ah
	mov	al,[es:si + wnd_item_strlen]
	add	si,ax
	add	si,wnd_item_string
	jmp	.find_item_under_cursor_item_loop
	.find_item_under_cursor_item_loop_end:
	xor	ax,ax
	mov	[hot_item],ax
	ret
	.find_item_under_cursor_window_loop_end:
	xor	ax,ax
	mov	[hot_window],ax
	mov	[hot_item],ax
	ret

wndmgr_push_input_event: ; input: bl = type, bh = data, ds = 0; preserves: everything
	push	cx
	push	si
	mov	si,input_event_queue - input_event_sz
	mov	cx,input_event_queue_count
	.loop:
	add	si,input_event_sz
	cmp	byte [si + input_event_type],0
	jz	.found
	loop	.loop
	jmp	.full
	.found:
	mov	[si + input_event_type],bx
	mov	cx,[cursor_x]
	mov	[si + input_event_cx],cx
	mov	cx,[cursor_y]
	mov	[si + input_event_cy],cx
	.full:
	pop	si
	pop	cx
	ret

wndmgr_mouse_buttons: ; input: al = left, ah = right, ds = 0; preserves: everything; can run in interrupts
	push	bx

	.left:
	cmp	al,[mouse_left_async]
	ja	.left_down
	jb	.left_up
	jmp	.right
	.left_down:
	mov	bx,input_event_type_left_down
	call	wndmgr_push_input_event
	jmp	.right
	.left_up:
	mov	bx,input_event_type_left_up
	call	wndmgr_push_input_event

	.right:
	cmp	ah,[mouse_right_async]
	ja	.right_down
	jb	.right_up
	jmp	.return
	.right_down:
	mov	bx,input_event_type_right_down
	call	wndmgr_push_input_event
	jmp	.return
	.right_up:
	mov	bx,input_event_type_right_up
	call	wndmgr_push_input_event

	.return:
	mov	[mouse_left_async],al
	mov	[mouse_right_async],ah
	pop	bx
	ret

wndmgr_move_cursor: ; input: ax = dx, dx = dy, ds = 0; preserves: everything; can run in interrupts
	push	bx
	push	cx
	push	ax
	push	dx

	.accelerate:
	mov	cx,dx
	mov	bx,ax
	mul	bx
	xchg	ax,cx
	mov	bx,ax
	mul	bx
	add	cx,ax
	pop	dx
	pop	ax
	push	ax
	push	dx
	cmp	cx,50
	jbe	.add
	shl	ax,1
	shl	dx,1

	.add:
	add	[cursor_x],ax
	add	[cursor_y],dx

	.clamp:
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
	pop	cx
	pop	bx
	ret

wndmgr_repaint_item_internal: ; input: es:si = item, cx = window, ds = 0; preserves: bp, si, es, ds
	call	.set_rect
	.dispatch:
	mov	al,[es:si + wnd_item_code]
	dec	al
	jz	class_button.on_draw
	dec	al
	jz	class_wndtitle.on_draw
	dec	al
	jz	class_static.on_draw
	dec	al
	jz	class_custom.on_draw
	jmp	exception_handler

	.set_rect:
	mov	ax,[es:si + wnd_item_l]
	add	ax,[wndmgr_repaint.wndrect + rect_l]
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	mov	ax,[es:si + wnd_item_r]
	add	ax,[wndmgr_repaint.wndrect + rect_l]
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	ax,[es:si + wnd_item_t]
	add	ax,[wndmgr_repaint.wndrect + rect_t]
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	mov	ax,[es:si + wnd_item_b]
	add	ax,[wndmgr_repaint.wndrect + rect_t]
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	di,wndmgr_repaint.itemrect
	ret

wndmgr_repaint_item: ; input: ax = window, es:bx = item, ds = 0; preserves: bp, es, ds
	push	ax
	mov	si,bx
	push	es
	mov	es,ax
	mov	ax,[es:wnd_l]
	mov	[wndmgr_repaint.wndrect + rect_l],ax
	mov	ax,[es:wnd_r]
	mov	[wndmgr_repaint.wndrect + rect_r],ax
	mov	ax,[es:wnd_t]
	mov	[wndmgr_repaint.wndrect + rect_t],ax
	mov	ax,[es:wnd_b]
	mov	[wndmgr_repaint.wndrect + rect_b],ax
	call	gfx_restore_beneath_cursor
	pop	es
	call	wndmgr_repaint_item_internal.set_rect
	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20 ; clear background
	pop	cx
	call	wndmgr_repaint_item_internal.dispatch
	jmp	gfx_draw_cursor

wndmgr_repaint: ; input: bx = draw background, ds = 0; preserves: everything
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es

	.draw_background:
	or	bx,bx
	jz	.skip_draw_background
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
	jmp	.skip_restore_cursor
	.skip_draw_background:
	call	gfx_restore_beneath_cursor
	.skip_restore_cursor:

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
	mov	si,wnd_desc_sz

	.draw_window_item:
	mov	al,[es:si + wnd_item_code]
	or	al,al
	jz	.next_window
	mov	bx,si
	pop	cx
	push	cx
	call	wndmgr_repaint_item_internal
	xor	ah,ah
	mov	al,[es:si + wnd_item_strlen]
	add	si,ax
	add	si,wnd_item_string
	jmp	.draw_window_item

	.draw_text_centered: ; TODO Move out into a separate function.
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

wndmgr_grow_items: ; input: ax = window, bx = shrink flag, ds = 0; preserves: everything
	push	ax
	push	bx
	push	cx
	push	es
	mov	es,ax
	or	bx,bx
	jz	.grow
	mov	bx,[es:wnd_l]
	sub	bx,[es:wnd_r]
	mov	cx,[es:wnd_t]
	sub	cx,[es:wnd_b]
	jmp	.do_loop
	.grow:
	mov	bx,[es:wnd_r]
	sub	bx,[es:wnd_l]
	mov	cx,[es:wnd_b]
	sub	cx,[es:wnd_t]
	.do_loop:
	sub	bx,wnd_client_off_x * 2
	sub	cx,wnd_client_off_x + wnd_client_off_y
	mov	ax,[es:wnd_description]
	mov	es,ax
	mov	si,wnd_desc_sz
	.item_loop:
	mov	al,[es:si]
	or	al,al
	jz	.return
	mov	ax,[es:si + wnd_item_flags]
	test	ax,wnd_item_flag_grow_l
	jz	.after_l
	add	[es:si + wnd_item_l],bx
	.after_l:
	test	ax,wnd_item_flag_grow_r
	jz	.after_r
	add	[es:si + wnd_item_r],bx
	.after_r:
	test	ax,wnd_item_flag_grow_t
	jz	.after_t
	add	[es:si + wnd_item_t],cx
	.after_t:
	test	ax,wnd_item_flag_grow_b
	jz	.after_b
	add	[es:si + wnd_item_b],cx
	.after_b:
	add	word [es:si + wnd_item_l],wnd_client_off_x
	add	word [es:si + wnd_item_r],wnd_client_off_x
	add	word [es:si + wnd_item_t],wnd_client_off_y
	add	word [es:si + wnd_item_b],wnd_client_off_y
	mov	al,[es:si + wnd_item_strlen]
	xor	ah,ah
	add	si,ax
	add	si,wnd_item_string
	jmp	.item_loop
	.return:
	pop	es
	pop	cx
	pop	bx
	pop	ax
	ret

do_wnd_destroy:
	push	ax
	push	ds
	xor	bx,bx
	mov	ds,bx
	call	dll_remove
	mov	bx,sys_heap_free
	int	0x20
	mov	bx,1
	call	wndmgr_repaint
	pop	ds
	pop	ax
	iret

do_wnd_create:
	mov	bx,sp
	mov	bx,[ss:bx + 2]
	push	ds
	push	es
	push	bx
	xor	bx,bx
	mov	ds,bx
	mov	cx,ax
	mov	ax,wnd_sz / 16
	mov	bx,sys_heap_alloc
	int	0x20
	pop	bx
	or	ax,ax
	jz	.return
	mov	es,ax
	mov	[es:wnd_segment],bx
	mov	[es:wnd_description],cx
	mov	bx,ax
	mov	ax,[.cascade]
	add	word [.cascade],50
	mov	word [es:wnd_l],ax
	mov	word [es:wnd_t],ax
	add	ax,200
	mov	word [es:wnd_r],ax
	mov	word [es:wnd_b],ax
	mov	ax,[window_list]
	call	dll_insert_end
	mov	ax,bx
	xor	bx,bx
	call	wndmgr_grow_items
	call	wndmgr_repaint
	.return:
	pop	es
	pop	ds
	iret
	.cascade: dw 20

wndmgr_find_item: ; input: ax = window, dx = item; output: es:si = description of item, cf = not found
	mov	es,ax
	mov	ax,[es:wnd_description]
	mov	es,ax
	mov	si,wnd_desc_sz
	.loop:
	mov	al,[es:si + wnd_item_code]
	or	al,al
	jz	.not_found
	mov	ax,[es:si + wnd_item_id]
	cmp	ax,dx
	je	.found
	mov	al,[es:si + wnd_item_strlen]
	xor	ah,ah
	add	si,ax
	add	si,wnd_item_string
	jmp	.loop
	.not_found:
	stc
	ret
	.found:
	clc
	ret

do_wnd_redraw:
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	xor	cx,cx
	mov	ds,cx
	mov	cx,ax
	call	wndmgr_find_item
	jc	exception_handler
	mov	ax,cx
	mov	bx,si
	call	wndmgr_repaint_item
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	iret

do_wndmgr_syscall:
	or	bl,bl
	jz	do_wnd_create
	dec	bl
	jz	do_wnd_destroy
	dec	bl
	jz	do_wnd_redraw
	jmp	exception_handler

window_list: dw 0
cursor_x_sync: dw 0
cursor_y_sync: dw 0
hot_window: dw 0
hot_item: dw 0
cursor_x: dw 10
cursor_y: dw 10
cursor_drawn_x: dw 10
cursor_drawn_y: dw 10
mouse_left_async: db 0
mouse_right_async: db 0
input_event_queue: times (input_event_sz * input_event_queue_count) db 0 ; TODO This is wasting space...
