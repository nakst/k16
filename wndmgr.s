; TODO Don't hlt if there are still events in the input queue. Currently key repeat misbehaves.
; TODO Menus: sending commands not working!!!
; TODO Menus: Window menu.
; TODO Menus: Clicking on the menubar to close the menu
; TODO Handling when both mouse buttons are pressed at the same time.
; TODO Clipping items to their window using the secondary clip rectangle.
; TODO Optimization: In wndmgr_repaint, immediately skip over windows that don't intersect the clip.
; TODO Optimization: class_button, class_static and class_number don't need to draw their own background if wndmgr_repaint has drawn it (wnd_flag_dialog mode).
; TODO Destroying/operating upon windows that have not been shown (see wnd_shown).
; TODO Automatic placement of the client content with wnd_flag_scrolled.
; TODO Optimization: Don't redraw the entire window when activating.
; TODO Optimization: Minimal repainting when resizing/moving windows.
; TODO Maximize windows if dragged to the top of the workspace.
; TODO Implement scroll bars.
; TODO Limiting the minimum size of a window.

%include "bin/reszpad.s"

wnd_l       equ 0x00
wnd_r       equ 0x02
wnd_t       equ 0x04
wnd_b       equ 0x06
wnd_segment equ 0x08
wnd_extra   equ 0x0A
wnd_shown   equ 0x0C ; byte
wnd_sz      equ 0x10
; item description follows

input_event_type equ 0x00
input_event_data equ 0x01
input_event_cx   equ 0x02
input_event_cy   equ 0x04
input_event_sz   equ 0x06

input_event_type_left_down  equ 0x01
input_event_type_right_down equ 0x02
input_event_type_left_up    equ 0x03
input_event_type_right_up   equ 0x04
input_event_type_key_down   equ 0x05
input_event_type_key_up     equ 0x06

input_event_queue_count equ 16 ; TODO Is this long enough?

key_ctrl   equ 29
key_lshift equ 42
key_rshift equ 54
key_alt    equ 56
key_capslk equ 58
key_numlk  equ 69
key_scrlk  equ 70

wnd_client_off_x equ 3
wnd_client_off_y equ 23

window_menu_id equ 1

wndmgr_send_callback: ; input: ax = window, es:bx = item(?), cx = message code, dx = message data 1, si = message data 2, di = message data 3, ds = 0; preserves: everything
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
	mov	ax,[es:wnd_sz + wnd_desc_callback]
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

wndmgr_window_drag_loop: ; ax = window, bl = move flag
	mov	[.move],bl

	mov	es,ax
	mov	bx,[es:wnd_l]
	mov	[.drag_rect + rect_l],bx
	mov	bx,[es:wnd_r]
	mov	[.drag_rect + rect_r],bx
	mov	bx,[es:wnd_t]
	mov	[.drag_rect + rect_t],bx
	mov	bx,[es:wnd_b]
	mov	[.drag_rect + rect_b],bx

	mov	word [gfx_clip_count],1
	mov	bx,[gfx_clip_seg]
	mov	es,bx
	mov	word [es:rect_l],0
	mov	bx,[gfx_width]
	mov	[es:rect_r],bx
	mov	word [es:rect_t],0
	mov	bx,[gfx_height]
	mov	[es:rect_b],bx

	call	gfx_restore_beneath_cursor
	call	.invert_drag_rect_border
	call	gfx_draw_cursor

	.halt_and_loop:
	; TODO Drag threshold.
	hlt
	.drag_loop:
	call	wndmgr_get_input_event
	jc	.no_event
	cmp	ax,input_event_type_left_up
	je	.exit_drag
	cmp	ax,input_event_type_right_up
	je	.exit_drag
	.no_event:
	mov	ax,[cursor_x_sync]
	mov	[.old_cursor + 0],ax
	mov	ax,[cursor_y_sync]
	mov	[.old_cursor + 2],ax
	call	wndmgr_update_cursor_pos
	jc	.halt_and_loop

	call	gfx_restore_beneath_cursor
	call	.invert_drag_rect_border
	mov	ax,[.old_cursor + 0]
	sub	ax,[cursor_x_sync]
	cmp	byte [.move],1
	jne	.no_move
	sub	[.drag_rect + rect_l],ax
	.no_move:
	sub	[.drag_rect + rect_r],ax
	mov	ax,[.old_cursor + 2]
	sub	ax,[cursor_y_sync]
	cmp	byte [.move],1
	jne	.no_move2
	sub	[.drag_rect + rect_t],ax
	.no_move2:
	sub	[.drag_rect + rect_b],ax
	call	.invert_drag_rect_border
	call	gfx_draw_cursor

	jmp	.drag_loop
	.exit_drag:
	call	gfx_restore_beneath_cursor
	call	.invert_drag_rect_border
	call	gfx_draw_cursor

	mov	bx,1
	mov	ax,[hot_window]
	call 	wndmgr_grow_items

	mov	ax,[hot_window]
	mov	es,ax
	mov	ax,[.drag_rect + rect_l]
	xchg	[es:wnd_l],ax
	mov	[.invert_rect + rect_l],ax
	mov	ax,[.drag_rect + rect_r]
	xchg	[es:wnd_r],ax
	mov	[.invert_rect + rect_r],ax
	mov	ax,[.drag_rect + rect_t]
	xchg	[es:wnd_t],ax
	mov	[.invert_rect + rect_t],ax
	mov	ax,[.drag_rect + rect_b]
	xchg	[es:wnd_b],ax
	mov	[.invert_rect + rect_b],ax

	xor	bx,bx
	mov	ax,[hot_window]
	call 	wndmgr_grow_items

	; TODO Instead of redrawing the window, 
	; 	- when moving: blit the old contents to the new location.
	;	- when resizing: redraw only the uncovered areas of the client.
	mov	word [gfx_clip_count],1
	mov	bx,[gfx_clip_seg]
	mov	es,bx
	mov	ax,[.drag_rect + rect_l]
	mov	[es:rect_l],ax
	mov	ax,[.drag_rect + rect_r]
	mov	[es:rect_r],ax
	mov	ax,[.drag_rect + rect_t]
	mov	[es:rect_t],ax
	mov	ax,[.drag_rect + rect_b]
	mov	[es:rect_b],ax
	call	wndmgr_repaint

	mov	word [gfx_clip_count],1
	mov	bx,[gfx_clip_seg]
	mov	es,bx
	mov	ax,[.invert_rect + rect_l] ; old rectangle
	mov	[es:rect_l],ax
	mov	ax,[.invert_rect + rect_r]
	mov	[es:rect_r],ax
	mov	ax,[.invert_rect + rect_t]
	mov	[es:rect_t],ax
	mov	ax,[.invert_rect + rect_b]
	mov	[es:rect_b],ax
	mov	ax,[.drag_rect + rect_l] ; minus new rectangle
	mov	[gfx_clip_rect + rect_l],ax
	mov	ax,[.drag_rect + rect_r]
	mov	[gfx_clip_rect + rect_r],ax
	mov	ax,[.drag_rect + rect_t]
	mov	[gfx_clip_rect + rect_t],ax
	mov	ax,[.drag_rect + rect_b]
	mov	[gfx_clip_rect + rect_b],ax
	call	gfx_clip_subtract
	call	wndmgr_repaint

	mov	word [hot_item],0
	jmp	wndmgr_process_input_event.after_mouse_drag

	.invert_drag_rect_border:
	mov	di,.invert_rect
	drag_rect_border_size equ 5

	mov	bx,[.drag_rect + rect_l]
	mov	[.invert_rect + rect_l],bx
	mov	bx,[.drag_rect + rect_r]
	mov	[.invert_rect + rect_r],bx
	mov	bx,[.drag_rect + rect_t]
	mov	[.invert_rect + rect_t],bx
	add	bx,drag_rect_border_size
	mov	[.invert_rect + rect_b],bx
	mov	bx,sys_draw_invert
	int	0x20
	mov	bx,[.drag_rect + rect_b]
	mov	[.invert_rect + rect_b],bx
	sub	bx,drag_rect_border_size
	mov	[.invert_rect + rect_t],bx
	mov	bx,sys_draw_invert
	int	0x20
	mov	bx,[.drag_rect + rect_t]
	add	bx,drag_rect_border_size
	mov	[.invert_rect + rect_t],bx
	mov	bx,[.drag_rect + rect_b]
	sub	bx,drag_rect_border_size
	mov	[.invert_rect + rect_b],bx
	mov	bx,[.drag_rect + rect_l]
	add	bx,drag_rect_border_size
	mov	[.invert_rect + rect_r],bx
	mov	bx,sys_draw_invert
	int	0x20
	mov	bx,[.drag_rect + rect_r]
	mov	[.invert_rect + rect_r],bx
	sub	bx,drag_rect_border_size
	mov	[.invert_rect + rect_l],bx
	mov	bx,sys_draw_invert
	int	0x20

	ret

	.drag_rect: dw 0,0,0,0
	.invert_rect: dw 0,0,0,0
	.old_cursor: dw 0,0
	.move: db 0

class_button:
	.on_left_down: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	or	word [es:bx + wnd_item_flags],wnd_item_flag_pushed
	call	wndmgr_repaint_item
	jmp	wndmgr_process_input_event.after_left_down

	.on_left_up: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	call	.update_push
	test	word [es:bx + wnd_item_flags],wnd_item_flag_pushed
	jz	.sent_click
	and	word [es:bx + wnd_item_flags],~wnd_item_flag_pushed
	push	bx
	push	ax
	call	wndmgr_repaint_item
	pop	ax
	pop	bx
	mov	cx,msg_btn_clicked
	mov	dx,[es:bx + wnd_item_id]
	call	wndmgr_send_callback
	.sent_click:
	jmp	wndmgr_process_input_event.after_left_up

	.on_mouse_drag: ; input: ax = window, es:bx = item, ds = 0; trashes: everything except ds
	mov	si,[es:bx + wnd_item_flags]
	call	.update_push
	cmp	si,[es:bx + wnd_item_flags]
	je	.no_push_change
	call	wndmgr_repaint_item
	.no_push_change:
	jmp	wndmgr_process_input_event.after_mouse_drag

	.on_draw: ; input: cx = window, ds = 0, es:si = item, di = .itemrect, ds = 0; preserves: ds, es, si, bp
	mov	bx,sys_draw_frame
	mov	cx,frame_3d_out
	test	word [es:si + wnd_item_flags],wnd_item_flag_pushed
	jz	.not_pushed
	mov	cx,frame_3d_in
	.not_pushed:
	int	0x20
	add	word [di + rect_l],2
	sub	word [di + rect_r],2
	add	word [di + rect_t],2
	sub	word [di + rect_b],2
	mov	cl,7
	mov	bx,sys_draw_block
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

	.update_push: ; preserves si
	and	word [es:bx + wnd_item_flags],~wnd_item_flag_pushed
	mov	cx,[cursor_x_sync]
	mov	dx,[cursor_y_sync]
	push	es
	mov	es,ax
	sub	cx,[es:wnd_l]
	sub	dx,[es:wnd_t]
	pop	es
	cmp	cx,[es:bx + wnd_item_l]
	jl	.not_pushed3
	cmp	cx,[es:bx + wnd_item_r]
	jge	.not_pushed3
	cmp	dx,[es:bx + wnd_item_t]
	jl	.not_pushed3
	cmp	dx,[es:bx + wnd_item_b]
	jge	.not_pushed3
	or	word [es:bx + wnd_item_flags],wnd_item_flag_pushed
	.not_pushed3:
	ret

class_wndtitle:
	.on_draw:
	mov	ax,[window_list]
	call	dll_last
	cmp	cx,ax
	mov	cl,1
	je	.active
	mov	cl,8
	.active:
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,0xF01
	jmp	wndmgr_repaint.draw_text_centered

	.on_mouse_drag:
	mov	bl,1
	jmp	wndmgr_window_drag_loop

class_scrollbar:
	.on_draw:
	test	word [es:bx + wnd_item_flags],wnd_item_flag_horz
	jz	.vert
	mov	cl,15
	mov	bx,sys_draw_block
	dec	word [di + rect_b]
	int	0x20
	mov	ax,[di + rect_b]
	mov	[di + rect_t],ax
	inc	ax
	mov	[di + rect_b],ax
	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20
	ret
	.vert:
	mov	cl,15
	mov	bx,sys_draw_block
	dec	word [di + rect_r]
	int	0x20
	mov	ax,[di + rect_r]
	mov	[di + rect_l],ax
	inc	ax
	mov	[di + rect_r],ax
	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20
	ret

class_reszpad:
	.on_draw:
	push	si

	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20

	mov	ax,12
	mov	cx,[di + rect_r]
	mov	dx,[di + rect_b]
	sub	cx,ax
	sub	dx,ax
	mov	di,.icon_rect
	mov	si,reszpad
	mov	bx,sys_draw_icon
	int	0x20
	
	pop	si
	ret

	.icon_rect: dw 0,12,0,12

	.on_mouse_drag:
	xor	bl,bl
	jmp	wndmgr_window_drag_loop

class_static:
	.on_draw:
	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20
	push	si
	xor	ax,ax
	test	word [es:si + wnd_item_flags],wnd_item_flag_bold
	jz	.not_bold
	inc	al
	.not_bold:
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

class_number:
	.on_draw:
	mov	ax,cx
	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20
	push	si
	push	di
	mov	bx,si
	mov	cx,msg_number_get
	mov	dx,[es:bx + wnd_item_id]
	xor	si,si
	mov	di,.value
	call	wndmgr_send_callback
	pop	di
	pop	si
	push	si
	xor	ax,ax
	test	word [es:si + wnd_item_flags],wnd_item_flag_bold
	jz	.not_bold
	inc	al
	.not_bold:
	push	ax
	mov	ax,[.value]
	mov	si,.strbuf + 5
	.loop:
	dec	si
	xor	dx,dx
	mov	bx,10
	div	bx
	add	dx,'0'
	mov	[si],dl
	or	ax,ax
	jnz	.loop
	pop	ax
	mov	cx,[di + rect_l]
	mov	dx,[di + rect_t]
	add	dx,[def_font]
	mov	bx,sys_draw_text
	int	0x20
	pop	si
	ret
	.value: dw 0
	.strbuf: db 0,0,0,0,0,0

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

	.on_mouse_drag:
	mov	cx,msg_custom_drag
	mov	dx,[es:bx + wnd_item_id]
	call	wndmgr_send_callback
	jmp	wndmgr_process_input_event.after_mouse_drag

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
	call	dll_alloc
	jc	out_of_memory_error
	mov	[menu_list],ax

	mov	cx,input_event_queue_count
	mov	si,input_event_queue
	.clear_queue:
	mov	byte [si + input_event_type],0
	add	si,input_event_sz
	loop	.clear_queue

	mov	word [gfx_clip_count],1
	mov	bx,[gfx_clip_seg]
	mov	es,bx
	mov	bx,[gfx_height]
	mov	word [es:rect_b],bx
	mov	word [es:rect_t],0
	mov	bx,[gfx_width]
	mov	word [es:rect_r],bx
	mov	word [es:rect_l],0
	call	wndmgr_repaint

%macro simulate_click 2
	mov	bx,%1
	mov	[cursor_x],bx
	mov	bx,%2
	mov	[cursor_y],bx
	mov	bx,input_event_type_left_down
	call	wndmgr_push_input_event
	mov	bx,input_event_type_left_up
	call	wndmgr_push_input_event
%endmacro

%macro simulate_keydown 1
	mov	bx,input_event_type_key_down | ((%1) << 8)
	call	wndmgr_push_input_event
%endmacro

;	simulate_keydown 20
;	simulate_keydown 21
;	simulate_keydown 75
;	simulate_keydown 28
;	simulate_keydown 28
;	simulate_keydown 72
;	simulate_keydown 28
;	simulate_keydown 59
;	simulate_keydown 72
;	simulate_keydown 28
;	simulate_keydown 72
;	simulate_click 250,216
;	simulate_click 233,84
;	simulate_click 384,124
;	simulate_click 10,10
;	simulate_click 15,35
	; maximum is input_event_queue_count / 2

;	mov	bx,124
;	mov	[cursor_x],bx
;	mov	bx,60
;	mov	[cursor_y],bx
;	mov	bx,input_event_type_left_down
;	call	wndmgr_push_input_event

	mov	ax,menubar_description
	mov	bx,sys_wnd_create
	int	0x20
	mov	[menubar_window],ax
	mov	es,ax
	mov	word [es:wnd_l],0
	mov	word [es:wnd_t],0
	mov	cx,[gfx_width]
	mov	word [es:wnd_r],cx
	mov	word [es:wnd_b],21
	mov	bx,sys_wnd_show
	int	0x20

	ret

menu_callback:
	cmp	dx,1
	jne	.return
	cmp	cx,msg_custom_draw
	je	.on_draw
	cmp	cx,msg_custom_mouse
	je	.on_mouse
	.return:
	iret

	.on_mouse:
	cmp	si,1
	je	.do_mouse
	cmp	si,0xFFFF
	je	.do_mouse
	iret

	.do_mouse:
	mov	bx,si
	mov	[menubar_callback.mouse_command],bl
	mov	es,ax
	mov	dx,[es:wnd_t]
	add	dx,4
	sub	dx,[cursor_y_sync]

	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	bx,[es:2]
	cmp	bx,window_menu_id
	jne	.normal_menu2
	xor	bx,bx
	mov	es,bx
	mov	bx,.window_menu
	jmp	.item_loop2
	.normal_menu2:
	mov	es,[es:0]
	mov	es,[es:wnd_segment]
	.item_loop2:
	mov	cl,[es:bx]
	or	cl,cl
	jz	.return
	test	word [es:bx + 3],menu_flag_separator
	jnz	.separator2
	add	dx,18
	jmp	.next_item2
	.separator2:
	add	dx,6
	.next_item2:
	cmp	dx,0
	jge	.found_hot_item
	xor	ch,ch
	add	bx,cx
	add	bx,5
	jmp	.item_loop2
	.found_hot_item:
	cmp	byte [menubar_callback.mouse_command],1
	je	.click_item
	add	dx,[cursor_y_sync]
	cmp	byte [.invert_rect_mode],2
	mov	byte [.invert_rect_mode],1
	jne	.no_prev_invert
	cmp	[.invert_rect + rect_b],dx
	je	.did_invert
	push	dx
	push	bx
	mov	bx,sys_wnd_redraw
	mov	dx,1
	int	0x20
	pop	bx
	pop	dx
	.no_prev_invert:
	test	word [es:bx + 3],menu_flag_separator
	jnz	.no_invert_separator
	mov	[.invert_rect + rect_b],dx
	sub	dx,18
	mov	[.invert_rect + rect_t],dx
	mov	bx,sys_wnd_redraw
	mov	dx,1
	int	0x20
	.did_invert:
	mov	byte [.invert_rect_mode],2
	iret
	.no_invert_separator:
	mov	byte [.invert_rect_mode],0
	iret
	.click_item:
	test	word [es:bx + 3],menu_flag_separator
	jnz	.return
	push	bx
	mov	bx,sys_wnd_get_extra
	int	0x20
	pop	bx
	call	wndmgr_close_menu
	cmp	word [es:2],window_menu_id
	jne	.normal_menu_click
	mov	dx,[bx + 1]
	mov	es,[es:0]
	mov	ax,es
	mov	es,[es:wnd_segment]
	jmp	.send_command
	.normal_menu_click:
	mov	es,[es:0]
	mov	ax,es
	mov	es,[es:wnd_segment]
	mov	dx,[es:bx + 1]
	.send_command:
	xor	bx,bx
	mov	cx,msg_menu_command
	call	wndmgr_send_callback
	mov	byte [.invert_rect_mode],0
	iret

	.on_draw:
	cmp	byte [.invert_rect_mode],1
	jne	.draw_background
	mov	ax,[di + rect_l]
	add	ax,4
	mov	[.invert_rect + rect_l],ax
	mov	ax,[di + rect_r]
	sub	ax,4
	mov	[.invert_rect + rect_r],ax
	mov	di,.invert_rect
	mov	bx,sys_draw_invert
	int	0x20
	iret

	.draw_background:
	or	si,si
	jnz	exception_handler
	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20
	mov	cx,frame_window
	mov	bx,sys_draw_frame
	int	0x20

	mov	cx,[di + rect_l]
	add	cx,14 ; x pos
	mov	dx,[di + rect_t]
	add	dx,4 ; y pos

	add	word [di + rect_l],6
	sub	word [di + rect_r],6

	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	bx,[es:2]
	cmp	bx,window_menu_id
	jne	.normal_menu
	xor	bx,bx
	mov	es,bx
	mov	bx,.window_menu
	jmp	.item_loop

	.normal_menu:
	mov	es,[es:0]
	mov	es,[es:wnd_segment]
	.item_loop:
	mov	al,[es:bx]
	or	al,al
	jz	.return
	push	ds
	mov	si,bx
	push	bx
	test	word [es:bx + 3],menu_flag_separator
	jnz	.separator
	mov	ax,es
	mov	ds,ax
	add	si,5
	mov	ax,0x0000
	mov	bx,sys_draw_text
	add	dx,12
	int	0x20
	add	dx,6
	jmp	.next_item
	.separator:
	push	cx
	mov	bx,dx
	add	bx,2
	mov	[di + rect_t],bx
	inc	bx
	mov	[di + rect_b],bx
	mov	cl,8
	mov	bx,sys_draw_block
	int	0x20
	inc	word [di + rect_t]
	inc	word [di + rect_b]
	mov	cl,15
	mov	bx,sys_draw_block
	int	0x20
	pop	cx
	add	dx,6
	.next_item:
	pop	bx
	pop	ds
	xor	ah,ah
	mov	al,[es:bx]
	add	bx,ax
	add	bx,5
	jmp	.item_loop

	.on_mouse_move:
	mov	ax,[menu_list]
	call	dll_last
	mov	es,ax
	mov	ax,[cursor_x_sync]
	cmp	ax,[es:wnd_l]
	jl	menubar_callback.on_mouse_move
	cmp	ax,[es:wnd_r]
	jge	menubar_callback.on_mouse_move
	mov	ax,[cursor_y_sync]
	cmp	ax,[es:wnd_t]
	jl	menubar_callback.on_mouse_move
	cmp	ax,[es:wnd_b]
	jge	menubar_callback.on_mouse_move
	mov	ax,[menu_list]
	call	dll_last
	jmp	menubar_callback.on_mouse_move_send_callback

	.invert_rect: dw 0,0,0,0
	.invert_rect_mode: db 0

	.window_menu:
	menu_start
	add_menu 'Close',menu_command_close,0
	menu_end

wndmgr_close_menu: ; input: ds = 0; preserves: ds
	mov	byte [menu_callback.invert_rect_mode],0
	push	ax
	push	bx
	push	dx
	cmp	word [menu_source],0
	je	.return
	mov	word [menu_source],0
	mov	ax,[menu_list]
	call	dll_last
	mov	bx,sys_wnd_destroy
	int	0x20
	mov	ax,[menubar_window]
	mov	byte [menubar_callback.invert_rect_mode],1
	mov	bx,sys_wnd_redraw
	mov	dx,1
	int	0x20
	mov	byte [menubar_callback.invert_rect_mode],0
	.return:
	pop	dx
	pop	bx
	pop	ax
	ret

menubar_callback:
	cmp	dx,1
	jne	.return
	cmp	cx,msg_custom_draw
	je	.on_draw
	cmp	cx,msg_custom_mouse
	je	.on_mouse
	iret

	.on_mouse:
	cmp	si,1
	je	.do_mouse
	cmp	si,0xFFFF
	je	.do_mouse
	iret
	
	.do_mouse:
	mov	bx,si
	mov	[.mouse_command],bl

	mov	bx,sys_wnd_get_rect
	mov	di,.out_rect
	int	0x20
	mov	cx,[di + rect_l]
	add	cx,15 ; x pos
	sub	cx,[cursor_x_sync]

	mov	ax,[window_list]
	call	dll_last
	call	dll_is_list
	jc	.return
	mov	es,ax

	push	ds
	mov	al,[es:wnd_sz + wnd_desc_sz]
	or	al,al
	mov	si,.untitled_string
	jz	.untitled2
	mov	ax,es
	mov	ds,ax
	mov	si,wnd_sz + wnd_desc_sz + wnd_item_string
	.untitled2:
	mov	al,1
	call	.hit_test_item
	pop	ds
	mov	si,window_menu_id
	mov	ax,[es:wnd_segment]
	mov	bx,[es:wnd_sz + wnd_desc_menubar]
	mov	es,ax
	jc	.clicked_first_item

	or	bx,bx
	jz	.return

	.item_loop2:
	mov	al,[es:bx]
	or	al,al
	je	.return
	push	ds
	mov	ax,es
	mov	ds,ax
	mov	si,bx
	add	si,5
	xor	al,al
	call	.hit_test_item
	pop	ds
	jc	.clicked_item
	xor	ah,ah
	mov	al,[es:bx]
	add	bx,ax
	add	bx,5
	jmp	.item_loop2

	.on_draw:
	cmp	byte [.invert_rect_mode],1
	jne	.draw_background
	mov	di,.invert_rect
	mov	bx,sys_draw_invert
	int	0x20
	iret

	.draw_background:
	or	si,si
	jnz	exception_handler
	mov	ax,[di + rect_b]
	dec	ax
	mov	[di + rect_b],ax
	mov	cl,0
	mov	bx,sys_draw_block
	int	0x20
	mov	[di + rect_t],ax
	inc	ax
	mov	[di + rect_b],ax
	mov	cl,15
	mov	bx,sys_draw_block
	int	0x20

	mov	cx,[di + rect_l]
	add	cx,16 ; x pos
	mov	dx,[di + rect_b]
	sub	dx,8 ; y pos

	mov	ax,[window_list]
	call	dll_last
	call	dll_is_list
	jc	.return
	mov	es,ax

	push	ds
	mov	al,[es:wnd_sz + wnd_desc_sz]
	or	al,al
	mov	si,.untitled_string
	jz	.untitled
	mov	ax,es
	mov	ds,ax
	mov	si,wnd_sz + wnd_desc_sz + wnd_item_string
	.untitled:
	mov	ax,0x0F01
	call	.draw_item
	pop	ds

	mov	bx,[es:wnd_sz + wnd_desc_menubar]
	or	bx,bx
	jz	.return
	mov	ax,[es:wnd_segment]
	mov	es,ax

	.item_loop:
	mov	al,[es:bx]
	or	al,al
	je	.return
	push	ds
	mov	ax,es
	mov	ds,ax
	mov	si,bx
	add	si,5
	mov	ax,0x0F00
	call	.draw_item
	pop	ds
	xor	ah,ah
	mov	al,[es:bx]
	add	bx,ax
	add	bx,5
	jmp	.item_loop
	
	.draw_item:
	push	es
	push	bx
	mov	bx,sys_draw_text
	int	0x20
	mov	di,.out_rect
	xor	bx,bx
	mov	es,bx
	mov	bx,sys_measure_text
	int	0x20
	add	cx,[es:.out_rect + rect_r]
	add	cx,16
	pop	bx
	pop	es
	ret
	
	.hit_test_item:
	push	es
	push	bx
	mov	di,.out_rect
	xor	bx,bx
	mov	es,bx
	mov	bx,sys_measure_text
	int	0x20
	mov	dx,cx
	sub	dx,8
	add	cx,[es:.out_rect + rect_r]
	add	cx,8
	cmp	cx,0
	jge	.hit_item
	add	cx,8
	pop	bx
	pop	es
	clc
	ret
	.hit_item:
	pop	bx
	pop	es
	stc
	ret

	.clicked_item:
	mov	si,[es:bx + 1]
	.clicked_first_item:
	cmp	[menu_source],si
	je	.close_menu_only
	call	wndmgr_close_menu
	mov	[menu_source],si
	add	dx,[cursor_x_sync]
	add	cx,[cursor_x_sync]
	mov	ax,menu_description
	mov	bx,sys_wnd_create
	int	0x20
	mov	bx,sys_wnd_get_extra
	mov	di,es
	int	0x20
	push	ax
	mov	ax,[window_list]
	call	dll_last
	mov	[es:0],ax
	pop	ax
	mov	[es:2],si
	mov	[.invert_rect + rect_l],dx
	mov	[.invert_rect + rect_r],cx
	mov	es,ax
	mov	[es:wnd_l],dx
	add	dx,100
	mov	[es:wnd_r],dx
	mov	cx,21
	mov	word [es:wnd_t],cx
	add	cx,8
	mov	bx,si
	push	es
	mov	es,di
	cmp	si,window_menu_id
	jne	.determine_height
	xor	bx,bx
	mov	es,bx
	mov	bx,menu_callback.window_menu
	.determine_height:
	mov	dl,[es:bx]
	or	dl,dl
	jz	.got_height
	test	word [es:bx + 3],menu_flag_separator
	jnz	.separator
	add	cx,12
	.separator:
	add	cx,6
	xor	dh,dh
	add	bx,dx
	add	bx,5
	jmp	.determine_height
	.got_height:
	pop	es
	mov	word [es:wnd_b],cx
	mov	bx,sys_wnd_show
	int	0x20
	mov	ax,[menubar_window]
	mov	es,ax
	mov	bx,[es:wnd_t]
	mov	[.invert_rect + rect_t],bx
	mov	bx,[es:wnd_b]
	mov	[.invert_rect + rect_b],bx
	mov	byte [.invert_rect_mode],1
	mov	bx,sys_wnd_redraw
	mov	dx,1
	int	0x20
	mov	byte [.invert_rect_mode],0
	iret

	.close_menu_only:
	cmp	byte [.mouse_command],0xFF
	je	.return
	call	wndmgr_close_menu
	iret

	.return:
	iret

	.on_mouse_move:
	mov	ax,[menubar_window]
	mov	es,ax
	mov	ax,[cursor_x_sync]
	cmp	ax,[es:wnd_l]
	jl	wndmgr_event_loop.loop
	cmp	ax,[es:wnd_r]
	jge	wndmgr_event_loop.loop
	mov	ax,[cursor_y_sync]
	cmp	ax,[es:wnd_t]
	jl	wndmgr_event_loop.loop
	cmp	ax,[es:wnd_b]
	jge	wndmgr_event_loop.loop
	mov	ax,[menubar_window]
	.on_mouse_move_send_callback:
	mov	bx,wnd_sz + wnd_desc_sz
	mov	cx,msg_custom_mouse
	mov	dx,1
	mov	si,0xFFFF
	call	wndmgr_send_callback
	jmp	wndmgr_event_loop.loop

	.out_rect: dw 0,0,0,0
	.untitled_string: db '???',0
	.invert_rect: dw 0,0,0,0
	.invert_rect_mode: db 0
	.mouse_command: db 0

wndmgr_event_loop:
	xor	ax,ax ; since apps iret to here after callback
	mov	ds,ax

	.wait:
	hlt ; Ideally we'd atomically sti and hlt, but I don't think we can.
	.loop:
	call	wndmgr_get_input_event
	jc	.no_input_event
	call	wndmgr_process_input_event
	.no_input_event:
	call	wndmgr_update_cursor_pos
	jc	.wait
	cmp	word [menu_source],0
	jnz	menu_callback.on_mouse_move
	mov	bx,[hot_item]
	or	bx,bx
	jz	.loop
	jmp	wndmgr_process_input_event.on_mouse_drag

wndmgr_update_cursor_pos: ; input: ds = 0; output: cf = set if cursor hasn't moved; trashes: all except ds
	mov	ax,[cursor_x]
	mov	bx,[cursor_y]
	cmp	ax,[cursor_drawn_x]
	jne	.cursor_moved
	cmp	bx,[cursor_drawn_y]
	jne	.cursor_moved
	stc
	ret

	.cursor_moved:
	cli ; this needs to be fast!
	call	gfx_restore_beneath_cursor
	mov	ax,[cursor_x]
	mov	bx,[cursor_y]
	mov	[cursor_drawn_x],ax
	mov	[cursor_drawn_y],bx
	mov	[cursor_x_sync],ax
	mov	[cursor_y_sync],bx
	call	gfx_draw_cursor
	sti
	clc
	ret

wndmgr_get_input_event: ; input: ds = 0; output: ax = type, cf = no event; trashes: all except ds
	.get_event:
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
	mov	byte [input_event_queue + (input_event_queue_count - 1) * input_event_sz + input_event_type],0

	pop	ax
	mov	[cursor_y_sync],ax
	pop	ax
	mov	[cursor_x_sync],ax
	pop	ax

	sti
	clc
	ret

	.no_event:
	sti
	stc
	ret

wndmgr_process_input_event: ; input: ds = 0, ax = data/type; trashes: all except ds
	.process:
	; call	heap_walk_quiet
	cmp	al,input_event_type_left_down
	je	.on_left_down
	cmp	al,input_event_type_left_up
	je	.on_left_up
	cmp	al,input_event_type_right_down
	je	.on_right_down
	cmp	al,input_event_type_right_up
	je	.on_right_up
	cmp	al,input_event_type_key_down
	je	.on_key_down
	cmp	al,input_event_type_key_up
	je	.on_key_up
	jmp	exception_handler

	.no_event:
	ret

	.on_key_down:
	cmp	ah,key_ctrl
	jne	.kd1
	or	byte [keyboard_state_bits],key_state_ctrl
	.kd1:
	cmp	ah,key_lshift
	jne	.kd2
	or	byte [keyboard_state_bits],key_state_lshift
	.kd2:
	cmp	ah,key_rshift
	jne	.kd3
	or	byte [keyboard_state_bits],key_state_rshift
	.kd3:
	cmp	ah,key_alt
	jne	.kd4
	or	byte [keyboard_state_bits],key_state_alt
	.kd4:
	cmp	ah,key_capslk
	jne	.kd5
	xor	byte [keyboard_state_bits],key_state_capslk
	.kd5:
	cmp	ah,key_numlk
	jne	.kd6
	xor	byte [keyboard_state_bits],key_state_numlk
	.kd6:
	cmp	ah,key_scrlk
	jne	.kd7
	xor	byte [keyboard_state_bits],key_state_scrlk
	.kd7:
	mov	cx,msg_key_down
	.send_key_event:
	mov	dl,ah
	mov	dh,[keyboard_state_bits]
	mov	ax,[window_list]
	call	dll_last
	call	dll_is_list
	jc	.no_event
	mov	es,ax
	jmp	wndmgr_send_callback

	.on_key_up:
	cmp	ah,key_ctrl
	jne	.ku1
	and	byte [keyboard_state_bits],~key_state_ctrl
	.ku1:
	cmp	ah,key_lshift
	jne	.ku2
	and	byte [keyboard_state_bits],~key_state_lshift
	.ku2:
	cmp	ah,key_rshift
	jne	.ku3
	and	byte [keyboard_state_bits],~key_state_rshift
	.ku3:
	cmp	ah,key_alt
	jne	.ku4
	and	byte [keyboard_state_bits],~key_state_alt
	.ku4:
	mov	cx,msg_key_up
	jmp	.send_key_event

	.on_left_down:
	call	.find_item_under_cursor
	mov	ax,[hot_window]
	or	ax,ax
	jz	.no_event
	mov	es,ax
	call	wndmgr_bring_to_front
	.skip_bring_to_front:
	mov	bx,[hot_item]
	or	bx,bx
	jz	.no_event
	mov	es,ax
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
	mov	cl,[es:bx + wnd_item_code]
	cmp	cl,wnd_item_code_button
	je	class_button.on_left_up
	cmp	cl,wnd_item_code_custom
	je	class_custom.on_left_up
	.after_left_up:
	xor	bx,bx
	mov	[hot_item],bx
	ret

	.on_right_down:
	call	.find_item_under_cursor
	mov	bx,[hot_item]
	or	bx,bx
	jz	.no_event
	mov	ax,[hot_window]
	mov	es,ax
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
	mov	cl,[es:bx + wnd_item_code]
	cmp	cl,wnd_item_code_custom
	je	class_custom.on_right_up
	.after_right_up:
	xor	bx,bx
	mov	[hot_item],bx
	ret

	.on_mouse_drag:
	mov	bx,[hot_item]
	mov	ax,[hot_window]
	mov	es,ax
	mov	cl,[es:bx + wnd_item_code]
	cmp	cl,wnd_item_code_button
	je	class_button.on_mouse_drag
	cmp	cl,wnd_item_code_custom
	je	class_custom.on_mouse_drag
	cmp	cl,wnd_item_code_title
	je	class_wndtitle.on_mouse_drag
	cmp	cl,wnd_item_code_reszpad
	je	class_reszpad.on_mouse_drag
	.after_mouse_drag:
	jmp	wndmgr_event_loop.loop

	.find_item_under_cursor:
	mov	ax,[menu_list]
	jmp	.find_item_under_cursor_window_loop
	.find_item_under_cursor_repeat:
	cmp	word [menu_source],0
	jnz	.close_menu_only
	cmp	ax,[menu_list]
	jne	.find_item_under_cursor_window_loop_end
	mov	ax,[window_list]
	.find_item_under_cursor_window_loop:
	call	dll_prev
	call	dll_is_list
	jc	.find_item_under_cursor_repeat
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
	mov	si,wnd_sz + wnd_desc_sz
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
	.close_menu_only:
	call	wndmgr_close_menu
	jmp	.find_item_under_cursor_window_loop_end

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

wndmgr_press_key: ; input: al = key, ah = up flag, ds = 0; preserves: everything; can run in interrupts
	push	bx
	mov	bl,input_event_type_key_down
	or	ah,ah
	jz	.down
	inc	bl
	.down:
	mov	bh,al
	call	wndmgr_push_input_event
	pop	bx
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
	dec	al
	jz	class_reszpad.on_draw
	dec	al
	jz	class_scrollbar.on_draw
	dec	al
	jz	class_number.on_draw
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

wndmgr_repaint_item: ; input: ax = window, es:bx = item, ds = 0; trashes everything except bp, es, ds
	push	ax
	mov	si,bx
	push	es
	mov	es,ax
	mov	cx,ax
	mov	ax,[es:wnd_l]
	mov	[wndmgr_repaint.wndrect + rect_l],ax
	mov	ax,[es:wnd_r]
	mov	[wndmgr_repaint.wndrect + rect_r],ax
	mov	ax,[es:wnd_t]
	mov	[wndmgr_repaint.wndrect + rect_t],ax
	mov	ax,[es:wnd_b]
	mov	[wndmgr_repaint.wndrect + rect_b],ax
	mov	word [gfx_clip_count],1
	mov	es,[gfx_clip_seg]
	mov	ax,[wndmgr_repaint.wndrect + rect_l]
	mov	[es:rect_l],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_r]
	mov	[es:rect_r],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_t]
	mov	[es:rect_t],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_b]
	mov	[es:rect_b],ax
	mov	ax,cx
	.subtract_loop:
	call	dll_next
	call	dll_is_list
	jc	.done_subtract
	mov	es,ax
	mov	cx,[es:wnd_l]
	mov	[gfx_clip_rect + rect_l],cx
	mov	cx,[es:wnd_r]
	mov	[gfx_clip_rect + rect_r],cx
	mov	cx,[es:wnd_t]
	mov	[gfx_clip_rect + rect_t],cx
	mov	cx,[es:wnd_b]
	mov	[gfx_clip_rect + rect_b],cx
	push	ax
	call	gfx_clip_subtract
	pop	ax
	jmp	.subtract_loop
	.done_subtract:
	call	gfx_restore_beneath_cursor
	pop	es
	call	wndmgr_repaint_item_internal.set_rect
;	mov	cl,7
;	mov	bx,sys_draw_block
;	int	0x20 ; clear background
	pop	cx
	call	wndmgr_repaint_item_internal.dispatch
	jmp	gfx_draw_cursor

wndmgr_draw_window_frame:
	mov	di,wndmgr_repaint.wndrect
	mov	bx,sys_draw_frame
	mov	cx,frame_window
	int	0x20

	mov	cl,7
	mov	di,wndmgr_repaint.itemrect

	mov	ax,[wndmgr_repaint.wndrect + rect_l]
	add	ax,2
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_t]
	add	ax,2
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_b]
	sub	ax,2
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.wndrect + rect_r]
	sub	ax,2
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	dec	ax
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.wndrect + rect_l]
	add	ax,3
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_r]
	sub	ax,3
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_t]
	add	ax,2
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.wndrect + rect_b]
	sub	ax,2
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	dec	ax
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.wndrect + rect_t]
	add	ax,wnd_client_off_y - 1
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20

	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_dialog
	jz	.skip_client_background_fill
	mov	ax,[wndmgr_repaint.wndrect + rect_t]
	add	ax,wnd_client_off_y
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_b]
	sub	ax,wnd_client_off_x
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20
	.skip_client_background_fill:

	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_scrolled
	jz	.skip_scroll_border_fill
	mov	ax,[wndmgr_repaint.wndrect + rect_t]
	add	ax,23
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_l]
	add	ax,3
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_r]
	sub	ax,4
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	cl,8
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.itemrect + rect_l]
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_b]
	sub	ax,4
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20
	inc	word [wndmgr_repaint.itemrect + rect_l]
	inc	word [wndmgr_repaint.itemrect + rect_r]
	inc	word [wndmgr_repaint.itemrect + rect_t]
	dec	word [wndmgr_repaint.itemrect + rect_b]
	mov	cl,0
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.itemrect + rect_t]
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_r]
	sub	ax,5
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.wndrect + rect_r]
	sub	ax,3
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	dec	ax
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	dec	word [wndmgr_repaint.itemrect + rect_t]
	mov	ax,[wndmgr_repaint.wndrect + rect_b]
	sub	ax,19
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	cl,15
	mov	bx,sys_draw_block
	int	0x20
	dec	ax
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	mov	ax,[wndmgr_repaint.itemrect + rect_r]
	sub	ax,17
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	mov	bx,sys_draw_block
	int	0x20
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_b]
	sub	ax,3
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20
	dec	ax
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_l]
	add	ax,3
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	mov	bx,sys_draw_block
	int	0x20
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	dec	word [wndmgr_repaint.itemrect + rect_t]
	dec	word [wndmgr_repaint.itemrect + rect_b]
	mov	cl,7
	mov	bx,sys_draw_block
	int	0x20
	sub	word [wndmgr_repaint.itemrect + rect_t],16
	mov	ax,[wndmgr_repaint.wndrect + rect_r]
	sub	ax,21
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	bx,sys_draw_block
	int	0x20
	add	ax,16
	mov	[wndmgr_repaint.itemrect + rect_r],ax
	mov	ax,[wndmgr_repaint.itemrect + rect_t]
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20
	mov	ax,[wndmgr_repaint.itemrect + rect_r]
	dec	ax
	mov	[wndmgr_repaint.itemrect + rect_l],ax
	mov	ax,[wndmgr_repaint.wndrect + rect_t]
	add	ax,24
	mov	[wndmgr_repaint.itemrect + rect_t],ax
	inc	ax
	mov	[wndmgr_repaint.itemrect + rect_b],ax
	mov	bx,sys_draw_block
	int	0x20
	.skip_scroll_border_fill:

	ret

wndmgr_repaint: ; input: ds = 0, [gfx_clip_seg]; preserves: everything except [gfx_clip_seg]
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es

	call	gfx_restore_beneath_cursor

	mov	ax,[menu_list]
	jmp	.window_loop
	.window_loop_repeat:
	cmp	ax,[menu_list]
	jne	.window_loop_end
	mov	ax,[window_list]
	.window_loop:
	call	dll_prev
	call	dll_is_list
	jc	.window_loop_repeat
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

	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_framed
	jz	.no_frame
	call	wndmgr_draw_window_frame
	.no_frame:

	mov	si,wnd_sz + wnd_desc_sz

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

	push	ax
	mov	es,ax
	mov	ax,[es:wnd_l]
	mov	[gfx_clip_rect + rect_l],ax
	mov	ax,[es:wnd_r]
	mov	[gfx_clip_rect + rect_r],ax
	mov	ax,[es:wnd_t]
	mov	[gfx_clip_rect + rect_t],ax
	mov	ax,[es:wnd_b]
	mov	[gfx_clip_rect + rect_b],ax
	call	gfx_clip_subtract
	pop	ax
	cmp	word [gfx_clip_count],0
	je	.window_loop_end

	jmp	.window_loop

	.window_loop_end:

	.draw_background:
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
	push	cx
	push	dx
	push	es
	mov	es,ax
	or	bx,bx
	jz	.grow
	mov	dx,[es:wnd_l]
	sub	dx,[es:wnd_r]
	mov	cx,[es:wnd_t]
	sub	cx,[es:wnd_b]
	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_framed
	jz	.do_loop
	add	dx,wnd_client_off_x * 2
	add	cx,wnd_client_off_x + wnd_client_off_y
	jmp	.do_loop
	.grow:
	mov	dx,[es:wnd_r]
	sub	dx,[es:wnd_l]
	mov	cx,[es:wnd_b]
	sub	cx,[es:wnd_t]
	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_framed
	jz	.do_loop
	sub	dx,wnd_client_off_x * 2
	sub	cx,wnd_client_off_x + wnd_client_off_y
	.do_loop:
	mov	si,wnd_sz + wnd_desc_sz
	.item_loop:
	mov	al,[es:si]
	or	al,al
	jz	.return
	mov	ax,[es:si + wnd_item_flags]
	test	ax,wnd_item_flag_grow_l
	jz	.after_l
	add	[es:si + wnd_item_l],dx
	.after_l:
	test	ax,wnd_item_flag_grow_r
	jz	.after_r
	add	[es:si + wnd_item_r],dx
	.after_r:
	test	ax,wnd_item_flag_grow_t
	jz	.after_t
	add	[es:si + wnd_item_t],cx
	.after_t:
	test	ax,wnd_item_flag_grow_b
	jz	.after_b
	add	[es:si + wnd_item_b],cx
	.after_b:
	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_framed
	jz	.next_item
	or	bx,bx
	jz	.grow2
	sub	word [es:si + wnd_item_l],wnd_client_off_x
	sub	word [es:si + wnd_item_r],wnd_client_off_x
	sub	word [es:si + wnd_item_t],wnd_client_off_y
	sub	word [es:si + wnd_item_b],wnd_client_off_y
	jmp	.next_item
	.grow2:
	add	word [es:si + wnd_item_l],wnd_client_off_x
	add	word [es:si + wnd_item_r],wnd_client_off_x
	add	word [es:si + wnd_item_t],wnd_client_off_y
	add	word [es:si + wnd_item_b],wnd_client_off_y
	.next_item:
	mov	al,[es:si + wnd_item_strlen]
	xor	ah,ah
	add	si,ax
	add	si,wnd_item_string
	jmp	.item_loop
	.return:
	pop	es
	pop	dx
	pop	cx
	pop	ax
	ret

wndmgr_redraw_title_and_menubar: ; input: ds = 0, ax = window to redraw title for; trashes everything except bp, ds
	call	dll_is_list
	jc	.menubar
	mov	es,ax
	mov	bl,[es:wnd_sz + wnd_desc_sz + wnd_item_code]
	cmp	bl,wnd_item_code_title
	jne	.menubar
	mov	bx,wnd_sz + wnd_desc_sz
	call	wndmgr_repaint_item
	.menubar:
	mov	ax,[menubar_window]
	mov	es,ax
	mov	bx,wnd_sz + wnd_desc_sz
	call	wndmgr_repaint_item
	ret

wndmgr_bring_to_front: ; input: ax = window, ds = 0; trashes everything except ax, ds
	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_menu
	jnz	.return

	call	dll_next
	call	dll_is_list
	jc	.already_activated

	call	dll_prev
	call	dll_remove
	mov	bx,ax
	mov	ax,[window_list]
	call	dll_insert_end
	mov	ax,bx

	mov	word [gfx_clip_count],1
	mov	bx,[gfx_clip_seg]
	mov	es,ax
	push	word [es:wnd_l]
	push	word [es:wnd_r]
	push	word [es:wnd_t]
	push	word [es:wnd_b]
	mov	es,bx
	pop	word [es:rect_b]
	pop	word [es:rect_t]
	pop	word [es:rect_r]
	pop	word [es:rect_l]
	; TODO Optimization: we only need to repaint the titlebar and the obscured regions.
	call	wndmgr_repaint

	push	ax
	call	dll_prev
	call	wndmgr_redraw_title_and_menubar
	pop	ax

	ret

	.already_activated:
	call	dll_prev
	.return:
	ret

do_wnd_destroy:
	push	ds
	push	es

	xor	bx,bx
	mov	ds,bx

	mov	es,ax

	mov	bx,[es:wnd_segment]
	xor	bx,bx
	jz	.keep_module
	sub	bx,module_sz / 16
	mov	es,bx
	dec	word [es:module_refs]
	jnz	.keep_module
	push	ax
	mov	ax,bx
	call	module_free
	pop	ax
	.keep_module:
	mov	es,ax

	mov	bx,[es:wnd_l]
	push	bx
	mov	bx,[es:wnd_r]
	push	bx
	mov	bx,[es:wnd_t]
	push	bx
	mov	bx,[es:wnd_b]
	push	bx
	mov	word [gfx_clip_count],1
	mov	bx,[gfx_clip_seg]
	mov	es,bx
	pop	bx
	mov	word [es:rect_b],bx
	pop	bx
	mov	word [es:rect_t],bx
	pop	bx
	mov	word [es:rect_r],bx
	pop	bx
	mov	word [es:rect_l],bx

	push	ax
	mov	bx,ax
	mov	ax,[window_list]
	call	dll_last
	mov	byte [.was_top],0
	cmp	ax,bx
	jne	.not_top
	mov	byte [.was_top],1
	.not_top:
	pop	ax

	call	dll_remove
	mov	bx,sys_heap_free
	int	0x20

	call	wndmgr_repaint

	cmp	byte [.was_top],1
	jne	.skip_redraw_title
	push	cx
	push	dx
	push	si
	push	di
	mov	ax,[window_list]
	call	dll_last
	call	wndmgr_redraw_title_and_menubar
	pop	di
	pop	si
	pop	dx
	pop	cx
	.skip_redraw_title:

	pop	es
	pop	ds
	iret

	.was_top: db 0

do_wnd_create:
	mov	bx,sp
	mov	bx,[ss:bx + 2]
	push	di
	push	si
	push	cx
	push	dx
	push	ds
	push	es
	push	bx
	or	bx,bx
	jz	.from_system
	sub	bx,module_sz / 16
	mov	es,bx
	inc	word [es:module_refs]
	.from_system:
	mov	si,ax
	mov	bx,wnd_desc_sz
	add	bx,si
	.get_size_loop:
	mov	al,[bx + wnd_item_code]
	or	al,al
	jz	.got_size
	mov	al,[bx + wnd_item_strlen]
	xor	ah,ah
	add	bx,ax
	add	bx,wnd_item_string
	jmp	.get_size_loop
	.got_size:
	inc	bx
	sub	bx,si
	mov	cx,bx
	add	bx,15
	shr	bx,1
	shr	bx,1
	shr	bx,1
	shr	bx,1
	mov	ax,wnd_sz / 16
	add	ax,bx
	mov	dx,ax
	add	ax,[si + wnd_desc_extra]
	mov	bx,sys_heap_alloc
	int	0x20
	xor	bx,bx
	mov	ds,bx
	pop	bx
	or	ax,ax
	jz	.return
	mov	es,ax
	add	dx,ax
	mov	[es:wnd_segment],bx
	mov	bx,ax
	mov	word [es:wnd_extra],dx
	mov	ax,bx
	pop	bx
	pop	ds
	push	ds
	push	bx
	mov	di,wnd_sz
	rep	movsb
	mov	cx,[es:wnd_sz + wnd_desc_extra]
	push	ax
	xor	al,al
	shl	cx,1
	shl	cx,1
	shl	cx,1
	shl	cx,1
	add	di,15
	and	di,~15
	rep	stosb
	pop	ax
	xor	bx,bx
	mov	ds,bx
	mov	bx,[gfx_width]
	sub	bx,[es:wnd_sz + wnd_desc_iwidth]
	shr	bx,1
	mov	word [es:wnd_l],bx
	mov	bx,[gfx_height]
	sub	bx,[es:wnd_sz + wnd_desc_iheight]
	shr	bx,1
	sub	bx,10
	mov	word [es:wnd_t],bx
	mov	bx,word [es:wnd_l]
	add	bx,[es:wnd_sz + wnd_desc_iwidth]
	mov	word [es:wnd_r],bx
	mov	bx,word [es:wnd_t]
	add	bx,[es:wnd_sz + wnd_desc_iheight]
	mov	word [es:wnd_b],bx
	mov	byte [es:wnd_shown],0
	.return:
	pop	es
	pop	ds
	pop	dx
	pop	cx
	pop	si
	pop	di
	iret

wndmgr_find_item: ; input: ax = window, dx = item; output: es:si = description of item, cf = not found; preserves: cx, dx
	mov	es,ax
	mov	si,wnd_sz + wnd_desc_sz
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

do_wnd_get_extra:
	mov	es,ax
	mov	bx,[es:wnd_extra]
	mov	es,bx
	iret

do_wnd_redraw:
	push	ax
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
	pop	ax
	iret

do_wnd_get_rect:
	push	es
	push	si
	push	ax
	push	cx
	mov	es,ax
	mov	cx,[es:wnd_l]
	mov	bx,[es:wnd_t]
	call	wndmgr_find_item
	jc	exception_handler
	mov	ax,[es:si + wnd_item_l]
	add	ax,cx
	mov	[di + rect_l],ax
	mov	ax,[es:si + wnd_item_r]
	add	ax,cx
	mov	[di + rect_r],ax
	mov	ax,[es:si + wnd_item_t]
	add	ax,bx
	mov	[di + rect_t],ax
	mov	ax,[es:si + wnd_item_b]
	add	ax,bx
	mov	[di + rect_b],ax
	pop	cx
	pop	ax
	pop	si
	pop	es
	iret

do_alert_error:
	push	ds
	cmp	ax,error_corrupt
	je	.case_corrupt
	cmp	ax,error_disk_io
	je	.case_disk_io
	cmp	ax,error_no_memory
	je	.case_no_memory
	cmp	ax,error_not_found
	je	.case_not_found
	mov	ax,.alert_other
	.create:
	xor	bx,bx
	mov	ds,bx
	mov	bx,sys_wnd_create
	int	0x20
	mov	bx,sys_wnd_show
	int	0x20
	pop	ds
	iret
	.case_corrupt:
	mov	ax,.alert_corrupt
	jmp	.create
	.case_disk_io:
	mov	ax,.alert_disk_io
	jmp	.create
	.case_no_memory:
	mov	ax,.alert_no_memory
	jmp	.create
	.case_not_found:
	mov	ax,.alert_not_found
	jmp	.create

	.alert_no_memory:
	wnd_start 'System Error', .callback, 0, 200, 100, wnd_flag_dialog, 0
	add_static 10, 180, 6, 21, 0, 0, 'Not enough memory is available.'
	add_static 10, 100, 21, 36, 0, 0, 'Close some apps and retry.'
	add_button 10, 90, 41, 64, 1, 0, 'OK'
	wnd_end
	.alert_not_found:
	wnd_start 'System Error', .callback, 0, 200, 100, wnd_flag_dialog, 0
	add_static 10, 180, 6, 21, 0, 0, 'The item was not found.'
	add_button 10, 90, 41, 64, 1, 0, 'OK'
	wnd_end
	.alert_disk_io:
	wnd_start 'System Error', .callback, 0, 200, 100, wnd_flag_dialog, 0
	add_static 10, 180, 6, 21, 0, 0, 'The requested data is inaccessible.'
	add_static 10, 100, 21, 36, 0, 0, 'The disk may be damaged.'
	add_button 10, 90, 41, 64, 1, 0, 'OK'
	wnd_end
	.alert_corrupt:
	wnd_start 'System Error', .callback, 0, 200, 100, wnd_flag_dialog, 0
	add_static 10, 180, 6, 21, 0, 0, 'The data has been corrupted.'
	add_static 10, 100, 21, 36, 0, 0, 'The disk may be damaged.'
	add_button 10, 90, 41, 64, 1, 0, 'OK'
	wnd_end
	.alert_other:
	wnd_start 'System Error', .callback, 0, 200, 100, wnd_flag_dialog, 0
	add_static 10, 180, 6, 21, 0, 0, 'The operation failed.'
	add_button 10, 90, 41, 64, 1, 0, 'OK'
	wnd_end
	.callback: 
	cmp	cx,msg_menu_command
	je	.menu_command
	cmp	dx,1
	jne	.done
	cmp	cx,msg_btn_clicked
	jne	.done
	mov	bx,sys_wnd_destroy
	int	0x20
	.done:
	iret
	.menu_command:
	cmp	dx,menu_command_close
	jne	.done
	mov	bx,sys_wnd_destroy
	int	0x20
	iret

do_cursor_get:
	push	ds
	xor	bx,bx
	mov	ds,bx
	mov	cx,[cursor_x_sync]
	mov	dx,[cursor_y_sync]
	pop	ds
	iret

do_wnd_show:
	push	cx
	push	dx
	push	si
	push	di
	push	es
	push	ds
	mov	es,ax
	cmp	byte [es:wnd_shown],1
	je	.return
	xor	bx,bx
	mov	ds,bx
	call	wndmgr_grow_items
	mov	bx,ax
	mov	ax,[window_list]
	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_menu
	jz	.not_menu
	mov	ax,[menu_list]
	.not_menu:
	call	dll_insert_end
	mov	ax,bx
	mov	es,ax
	mov	byte [es:wnd_shown],1
	mov	cx,[es:wnd_l]
	mov	dx,[es:wnd_r]
	mov	si,[es:wnd_t]
	mov	di,[es:wnd_b]
	mov	word [gfx_clip_count],1
	mov	bx,[gfx_clip_seg]
	mov	es,bx
	mov	[es:rect_l],cx
	mov	[es:rect_r],dx
	mov	[es:rect_t],si
	mov	[es:rect_b],di
	call	wndmgr_repaint
	mov	es,ax
	test	word [es:wnd_sz + wnd_desc_flags],wnd_flag_menu
	jnz	.return
	push	ax
	call	dll_prev
	call	wndmgr_redraw_title_and_menubar
	pop	ax
	.return:
	pop	ds
	pop	es
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
	dec	bl
	jz	do_wnd_get_extra
	dec	bl
	jz	do_alert_error
	dec	bl
	jz	do_wnd_get_rect
	dec	bl
	jz	do_cursor_get
	dec	bl
	jz	do_wnd_show
	jmp	exception_handler

menubar_description:
	wnd_start_no_decor menubar_callback, 0, 0, 0, wnd_flag_menu, 0
	add_custom 0, 0, 0, 0, 1, wnd_item_flag_grow_r | wnd_item_flag_grow_b, ''
	wnd_end

menu_description:
	wnd_start_no_decor menu_callback, 4, 0, 0, wnd_flag_menu, 0
	add_custom 0, 0, 0, 0, 1, wnd_item_flag_grow_r | wnd_item_flag_grow_b, ''
	wnd_end

window_list: dw 0
menu_list: dw 0
menubar_window: dw 0
cursor_x_sync: dw 0
cursor_y_sync: dw 0
hot_window: dw 0
hot_item: dw 0
cursor_x: dw 30
cursor_y: dw 45
cursor_drawn_x: dw 30
cursor_drawn_y: dw 45
mouse_left_async: db 0
mouse_right_async: db 0
menu_source: dw 0
keyboard_state_bits: db 0
input_event_queue: times (input_event_sz * input_event_queue_count) db 0 ; TODO This is wasting space...
