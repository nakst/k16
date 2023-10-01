; TODO Implement do_hit_test_text.
; TODO Minimal redrawing.
; TODO Scrolling.
; TODO Backspace/delete.
; TODO Other motions.
; TODO Selections.
; TODO File commands.
; TODO Edit commands.

[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

id_textbox equ 1

line_start  equ 0x00
line_nbytes equ 0x02 ; excluding newline char
line_sz     equ 0x04

linebuf_sz equ 0x100

window_lines    equ 0x00
window_data     equ 0x02
window_nbytes   equ 0x04
window_nlines   equ 0x06
window_actline  equ 0x08
window_oalnb    equ 0x0A ; original active line nbytes; *includes* newline char
window_caret_x  equ 0x0C
window_caret_xp equ 0x0E ; in pixels
window_linebuf  equ 0x10
window_sz       equ (linebuf_sz + window_linebuf)

command_new        equ 1
command_open       equ 2
command_save       equ 3
command_save_as    equ 4
command_cut        equ 5
command_copy       equ 6
command_paste      equ 7
command_delete     equ 8
command_select_all equ 9

redraw_what_all   equ 0
redraw_what_line  equ 1
redraw_what_caret equ 2

start:
	mov	ax,window_description
	mov	bx,sys_wnd_create
	int	0x20
	or	ax,ax
	jz	.return
	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	word [es:window_nbytes],1
	mov	word [es:window_nlines],1
	mov	cx,ax
	mov	ax,(line_sz + 15) / 16
	mov	bx,sys_heap_alloc
	int	0x20
	mov	[es:window_lines],ax
	mov	ax,(1 + 15) / 16
	mov	bx,sys_heap_alloc
	int	0x20
	mov	[es:window_data],ax
	mov	ax,cx
	mov	bx,sys_wnd_show
	int	0x20
	cmp	word [es:window_lines],0
	jz	.error
	cmp	word [es:window_data],0
	jz	.error
	push	es
	mov	ax,[es:window_lines]
	mov	es,ax
	mov	word [es:line_start],0
	mov	word [es:line_nbytes],0
	pop	es
	push	es
	mov	word [es:window_oalnb],1
	mov	ax,[es:window_data]
	mov	es,ax
	mov	byte [es:0],10
	pop	es
	.return:
	iret
	.error:
	mov	ax,[es:window_lines]
	mov	bx,sys_heap_free
	int	0x20
	mov	ax,[es:window_data]
	mov	bx,sys_heap_free
	int	0x20
	mov	bx,sys_wnd_destroy
	int	0x20
	mov	bx,sys_alert_error
	mov	ax,error_no_memory
	int	0x20
	iret

draw_line_background:
	push	ds
	push	cx
	push	dx
	mov	ax,cs
	mov	ds,ax
	mov	bx,sys_draw_block
	mov	di,out_rect
	mov	ax,[cs:draw_dispatch.left]
	mov	[di + rect_l],ax
	mov	ax,[cs:draw_dispatch.right]
	mov	[di + rect_r],ax
	mov	[di + rect_t],dx
	add	dx,[draw_all.line_ascent]
	add	dx,[draw_all.line_descent]
	mov	[di + rect_b],dx
	mov	cl,15
	int	0x20
	pop	dx
	pop	cx
	pop	ds
	ret

draw_caret: ; ds = window extra
	add	dx,[cs:draw_all.line_ascent]
	mov	si,window_linebuf
	mov	bx,[window_caret_x]
	push	word [si + bx]
	mov	byte [si + bx],0
	push	bx
	push	es
	push	ds
	mov	ax,cs
	mov	es,ax
	push	ax
	xor	ax,ax
	mov	di,out_rect
	mov	bx,sys_measure_text
	int	0x20
	pop	ax
	mov	ds,ax
	mov	ax,[out_rect + rect_r]
	add	ax,cx
	mov	[caret_rect + rect_r],ax
	dec	ax
	mov	[caret_rect + rect_l],ax
	mov	ax,[out_rect + rect_t]
	add	ax,dx
	mov	[caret_rect + rect_t],ax
	mov	ax,[out_rect + rect_b]
	add	ax,dx
	mov	[caret_rect + rect_b],ax
	mov	di,caret_rect
	mov	bx,sys_draw_invert
	int	0x20
	pop	ds
	pop	es
	pop	bx
	pop	word [si + bx]
	sub	dx,[cs:draw_all.line_ascent]
	ret

draw_line: ; input: cx = x pos, dx = y pos, ds = window extra, es = line data, bp = line index
	xor	ax,ax ; black, not bold

	mov	bx,bp
	shl	bx,1
	shl	bx,1
	mov	si,[es:bx + line_start]
	mov	bx,[es:bx + line_nbytes]

	cmp	bp,[window_actline]
	je	.actline
	push	ds
	mov	ds,[window_data]
	jmp	.draw_line
	.actline:
	push	ds
	mov	si,window_linebuf

	.draw_line:
	push	word [si + bx]
	mov	byte [si + bx],0
	push	bx
	mov	bx,sys_draw_text
	add	dx,[cs:draw_all.line_ascent]
	int	0x20
	sub	dx,[cs:draw_all.line_ascent]
	pop	bx
	pop	word [si + bx]
	pop	ds

	.draw_caret:
	cmp	bp,[window_actline]
	jne	.return
	call	draw_caret

	.return:
	ret

draw_all:
	.draw_background:
	push	cx
	mov	cl,15
	mov	bx,sys_draw_block
	int	0x20
	pop	cx

	.prepare_line_loop:
	mov	ax,es ; ds = window extra
	mov	ds,ax
	mov	ax,[es:window_lines]
	mov	es,ax ; es = line data
	xor	bp,bp ; bp = line index

	.line_loop:
	call	draw_line
	push	ds
	mov	ax,cs
	mov	ds,ax
	add	dx,[.line_ascent]
	add	dx,[.line_descent]
	pop	ds
	inc	bp
	cmp	bp,[window_nlines]
	jne	.line_loop

	.return:
	ret

	.line_ascent: dw 10 ; TODO Get this from sys_measure_text.
	.line_descent: dw 4 ; TODO Get this from sys_measure_text.

draw_dispatch:
	push	di
	mov	di,caret_rect
	mov	bx,sys_draw_invert
	int	0x20
	pop	di

	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	ds,si
	call	.get_start_point

	xor	bx,bx
	xchg	bx,[cs:redraw_what]
	or	bx,bx
	je	.all
	dec	bx
	je	.line
	dec	bx
	je	.caret
	iret

	.all:
	call	draw_all
	iret

	.line:
	mov	bp,[cs:redraw_line]
	call	.add_y_offset_for_line
	mov	ax,es
	mov	ds,ax
	mov	es,[window_lines]
	call	draw_line_background
	call	draw_line
	iret

	.caret:
	mov	bp,[es:window_actline]
	call	.add_y_offset_for_line
	mov	ax,es
	mov	ds,ax
	call	draw_caret
	iret

	.get_start_point:
	mov	cx,[di + rect_l]
	mov	dx,[di + rect_t]
	add	cx,4
	add	dx,2
	mov	ax,[di + rect_r]
	mov	[cs:.right],ax
	mov	ax,[di + rect_l]
	mov	[cs:.left],ax
	ret

	.add_y_offset_for_line: ; bp = line index
	mov	ax,[cs:draw_all.line_ascent]
	add	ax,[cs:draw_all.line_descent]
	push	dx
	mul	bp
	pop	dx
	add	dx,ax
	ret

	.left: dw 0
	.right: dw 0

redraw_all:
	push	bx
	push	dx
	mov	dx,id_textbox
	mov	bx,sys_wnd_redraw
	int	0x20
	pop	dx
	pop	bx
	ret

redraw_actline:
	push	bx
	push	dx
	mov	word [cs:redraw_what],redraw_what_line
	mov	bx,[es:window_actline]
	mov	[cs:redraw_line],bx
	mov	dx,id_textbox
	mov	bx,sys_wnd_redraw
	int	0x20
	pop	dx
	pop	bx
	ret

redraw_caret:
	push	bx
	push	dx
	mov	word [cs:redraw_what],redraw_what_caret
	mov	dx,id_textbox
	mov	bx,sys_wnd_redraw
	int	0x20
	pop	dx
	pop	bx
	ret

memmove: ; input: si = source, di = move offset, cx = count, es = segment
	cmp	di,0
	je	.return
	jg	.backwards

	.forwards:
	push	ds
	push	es
	pop	ds
	add	di,si
	rep	movsb
	pop	ds
	jmp	.return

	.backwards:
	std
	push	ds
	push	es
	pop	ds
	add	si,cx
	dec	si
	add	di,si
	rep	movsb
	pop	ds
	cld

	.return:
	ret

load_active_line: ; input: es = window extra; trashes: everything except es
	mov	bx,[es:window_actline]
	push	es
	mov	ds,[es:window_data]
	shl	bx,1
	shl	bx,1
	mov	es,[es:window_lines]
	mov	cx,[es:bx + line_nbytes]
	mov	si,[es:bx + line_start]
	pop	es
	inc	cx
	mov	[es:window_oalnb],cx
	dec	cx
	mov	di,window_linebuf
	rep	movsb
	ret

merge_active_line: ; input: es = window extra; trashes: everything except es
	; TODO Check for 64KB overflow.

	; Check if we need to reallocate.
	mov	cx,[es:window_nbytes]
	sub	cx,[es:window_oalnb]
	push	es
	mov	bx,[es:window_actline]
	mov	es,[es:window_lines]
	shl	bx,1
	shl	bx,1
	add	cx,[es:bx + line_nbytes]
	inc	cx ; newline char
	pop	es
	mov	bx,0xFFFF
	mov	dx,bx
	.count_magnitude:
	inc	bx
	shr	cx,1
	jnz	.count_magnitude
	mov	ax,[es:window_nbytes]
	.count_old_magnitude:
	inc	dx
	shr	ax,1
	jnz	.count_old_magnitude
	cmp	bx,dx
	je	.done_reallocate

	; Reallocate.
	mov	ax,1
	mov	cx,bx
	or	cx,cx
	jz	.got_new_size
	.get_new_size:
	shl	ax,1
	loop	.get_new_size
	.got_new_size:
	add	ax,7
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jz	.fail
	push	ds
	push	es
	mov	cx,[es:window_nbytes]
	mov	ds,[es:window_data]
	mov	es,ax
	xor	di,di
	xor	si,si
	rep	movsb
	pop	es
	pop	ds
	xchg	ax,[es:window_data]
	mov	bx,sys_heap_free
	int	0x20
	.done_reallocate:

	; Move lines after the active line in the data buffer.
	mov	bx,[es:window_actline]
	shl	bx,1
	shl	bx,1
	push	es
	mov	es,[es:window_lines]
	mov	di,[es:bx + line_nbytes]
	inc	di
	mov	si,[es:bx + line_start]
	pop	es
	add	si,[es:window_oalnb]
	sub	di,[es:window_oalnb]
	mov	cx,[es:window_nbytes]
	sub	cx,si
	push	es
	push	di
	mov	es,[es:window_data]
	call	memmove
	pop	di
	pop	es

	; Update the line_start values and window_nbytes.
	push	es
	mov	bx,[es:window_actline]
	inc	bx
	mov	cx,[es:window_nlines]
	sub	cx,bx
	jz	.update_loop_done
	shl	bx,1
	shl	bx,1
	mov	es,[es:window_lines]
	.update_loop:
	add	[es:bx + line_start],di
	add	bx,4
	loop	.update_loop
	.update_loop_done:
	pop	es
	add	[es:window_nbytes],di

	; Copy the actline data from the linebuf.
	mov	bx,[es:window_actline]
	shl	bx,1
	shl	bx,1
	push	ds
	push	es
	mov	ax,es
	mov	ds,ax
	mov	es,[window_lines]
	mov	bx,[window_actline]
	shl	bx,1
	shl	bx,1
	mov	di,[es:bx + line_start]
	mov	si,window_linebuf
	mov	cx,[es:bx + line_nbytes]
	mov	[window_oalnb],cx
	mov	es,[window_data]
	rep	movsb
	mov	byte [es:di],10 ; newline char
	inc	word [window_oalnb]
	pop	es
	pop	ds

	clc
	ret

	.fail:
	stc
	ret

key_typed_insert_newline:
	mov	bx,sys_wnd_get_extra
	int	0x20

	; Truncate the active line to the caret.
	push	es
	mov	dx,[es:window_caret_x]
	mov	bx,[es:window_actline]
	mov	es,[es:window_lines]
	shl	bx,1
	shl	bx,1
	mov	si,[es:bx + line_start] ; si = initial start for newline
	add	si,dx
	inc	si
	xchg	dx,[es:bx + line_nbytes]
	pop	es
	sub	dx,[es:window_caret_x] ; dx = initial nbytes in newline

	; Merge the active line.
	push	ax
	push	dx
	push	si
	call	merge_active_line
	pop	si
	pop	dx
	pop	ax
	jc	.fail

	; Insert a new line.
	mov	bx,[es:window_nlines]
	mov	cx,bx
	inc	cx ; TODO Check for 16-bit overflow.
	mov	[es:window_nlines],cx
	and	bx,cx
	jz	.grow_line_array
	.line_array_ready:
	sub	cx,[es:window_actline]
	dec	cx
	mov	bx,[es:window_actline]
	inc	bx
	mov	[es:window_actline],bx
	shl	bx,1
	shl	bx,1
	push	es
	mov	es,[es:window_lines]
	.line_move_loop:
	xchg	si,[es:bx + line_start]
	xchg	dx,[es:bx + line_nbytes]
	add	bx,4
	loop	.line_move_loop
	pop	es

	; Start writing to the new line.
	mov	word [es:window_oalnb],0
	mov	bx,[es:window_actline]
	push	es
	shl	bx,1
	shl	bx,1
	mov	es,[es:window_lines]
	mov	cx,[es:bx + line_nbytes]
	pop	es
	or	cx,cx
	jz	.skip_shuffle
	mov	bx,[es:window_caret_x]
	xor	di,di
	.shuffle_buffer:
	mov	dl,[es:window_linebuf + bx + di]
	mov	[es:window_linebuf + di],dl
	inc	di
	loop	.shuffle_buffer
	.skip_shuffle:
	mov	word [es:window_caret_x],0

	; TODO Minimal redrawing.
	call	redraw_all

	iret

	.grow_line_array:
	push	ax
	push	cx
	push	si
	mov	ax,[es:window_nlines]
	inc	ax
	shr	ax,1
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jz	.grow_line_array_fail
	mov	bx,ax ; bx = new lines
	xchg	ax,[es:window_lines] ; ax = old lines
	push	ds
	push	es
	mov	cx,[es:window_nlines]
	dec	cx
	shl	cx,1
	shl	cx,1
	xor	si,si
	xor	di,di
	mov	ds,ax
	mov	es,bx
	rep	movsb
	mov	bx,sys_heap_free
	int	0x20
	pop	es
	pop	ds
	pop	si
	pop	cx
	pop	ax
	jmp	.line_array_ready
	.grow_line_array_fail:
	pop	si
	pop	cx
	pop	ax
	dec	word [es:window_nlines]
	jmp	.fail

	.fail:
	; TODO Undo the line truncation.
	mov	ax,error_no_memory
	mov	bx,sys_alert_error
	int	0x20
	iret

key_typed_insert_char:
	; TODO Caps lock and numpad.

	test	dh,key_state_ctrl | key_state_alt
	jnz	.return
	test	dh,key_state_lshift | key_state_rshift
	jz	.no_shift
	or	dl,0x80
	.no_shift:
	push	ax
	mov	al,dl
	mov	bx,key_lookup
	xlat
	mov	dl,al
	pop	ax

	or	dl,dl ; dl = ascii character
	jz	.return

	cmp	dl,10
	je	key_typed_insert_newline

	mov	bx,sys_wnd_get_extra
	int	0x20

	push	ax

	mov	cx,es
	mov	bx,[es:window_actline]
	mov	ax,[es:window_lines]
	mov	es,ax
	shl	bx,1
	shl	bx,1
	mov	di,[es:bx + line_nbytes]
	cmp	di,linebuf_sz - 1
	je	.no_room
	inc	word [es:bx + line_nbytes]

	mov	es,cx
	mov	bx,[es:window_caret_x]
	.move_loop:
	xchg	[es:window_linebuf + bx],dl
	inc	bx
	cmp	bx,di
	jle	.move_loop
	inc	word [es:window_caret_x]

	.no_room:

	pop	ax

	.redraw:
	; TODO Minimal redrawing.
	call	redraw_actline

	.return:
	iret

set_caret_xp:
	cmp	word [es:window_caret_xp],0
	jne	.return
	push	bx
	push	ds
	push	es
	mov	bx,[es:window_actline]
	mov	ds,[es:window_lines]
	shl	bx,1
	shl	bx,1
	mov	si,[bx + line_start]
	mov	ds,[es:window_data]
	mov	bx,[es:window_caret_x]
	add	bx,si
	push	word [bx]
	mov	byte [bx],0
	xor	ax,ax
	mov	es,ax
	mov	di,out_rect
	push	bx
	mov	bx,sys_measure_text
	int	0x20
	pop	bx
	pop	word [bx]
	mov	bx,[es:di + rect_r]
	pop	es
	mov	[es:window_caret_xp],bx
	pop	ds
	pop	bx
	.return:
	ret

move_caret_to_xp:
	push	bx
	push	ds
	mov	bx,[es:window_actline]
	mov	ds,[es:window_lines]
	shl	bx,1
	shl	bx,1
	mov	si,[bx + line_start]
	mov	bx,[bx + line_nbytes]
	mov	di,[es:window_caret_xp]
	mov	ds,[es:window_data]
	push	word [bx]
	mov	byte [bx],0
	push	bx
	mov	bx,sys_hit_test_text
	int	0x20
	pop	bx
	pop	word [bx]
	mov	[es:window_caret_x],di
	pop	ds
	pop	bx
	ret

key_typed:
	mov	bx,sys_wnd_get_extra
	int	0x20
	cmp	dl,72
	je	.up_arrow
	cmp	dl,80
	je	.down_arrow
	cmp	dl,59 ; TODO Temporary.
	je	.debug
	mov	word [es:window_caret_xp],0

	cmp	dl,75
	je	.left_arrow
	cmp	dl,77
	je	.right_arrow
	jmp	key_typed_insert_char

	.left_arrow:
	mov	cl,[es:window_caret_x]
	or	cl,cl
	jz	.return
	dec	cl
	mov	[es:window_caret_x],cl
	call	redraw_caret
	iret

	.right_arrow:
	mov	cl,[es:window_caret_x]
	mov	bx,[es:window_actline]
	shl	bx,1
	shl	bx,1
	push	es
	mov	es,[es:window_lines]
	cmp	cl,[es:bx + line_nbytes]
	pop	es
	je	.return
	inc	cl
	mov	[es:window_caret_x],cl
	call	redraw_caret
	iret

	.up_arrow:
	push	ax
	call	merge_active_line
	mov	bx,[es:window_actline]
	or	bx,bx
	jz	.at_start
	call	set_caret_xp
	dec	bx
	mov	[es:window_actline],bx
	call	load_active_line
	.at_start:
	call	move_caret_to_xp
	pop	ax
	call	redraw_caret
	iret

	.down_arrow:
	push	ax
	call	merge_active_line
	mov	bx,[es:window_actline]
	inc	bx
	cmp	bx,[es:window_nlines]
	je	.at_end
	call	set_caret_xp
	mov	[es:window_actline],bx
	call	load_active_line
	.at_end:
	call	move_caret_to_xp
	pop	ax
	call	redraw_caret
	iret

	.debug:
	debug_log_16 [es:window_nbytes]
	debug_log_16 [es:window_nlines]
	debug_log_16 [es:window_actline]
	debug_log_16 [es:window_caret_x]
	debug_log_16 [es:window_oalnb]
	debug_log_16 [es:window_linebuf]
	push	es
	mov	cx,[es:window_nlines]
	mov	es,[es:window_lines]
	xor	bx,bx
	.debug_line:
	debug_log_16 [es:bx + line_start]
	debug_log_16 [es:bx + line_nbytes]
	add	bx,4
	loop	.debug_line
	pop	es
	push	es
	mov	cx,[es:window_nbytes]
	inc	cx
	shr	cx,1
	mov	es,[es:window_data]
	xor	bx,bx
	.debug_data:
	debug_log_16 [es:bx]
	add	bx,2
	loop	.debug_data
	pop	es
	iret

	.return:
	iret

window_callback:
	cmp	cx,msg_menu_command
	je	.menu_command
	
	cmp	cx,msg_custom_draw
	je	.custom_draw

	cmp	cx,msg_key_down
	je	key_typed

	iret

	.custom_draw:
	cmp	dx,id_textbox
	je	draw_dispatch
	iret

	.menu_command:
	cmp	dx,menu_command_close
	je	.close
	iret

	.close:
	; TODO Free memory.
	mov	bx,sys_wnd_destroy
	int	0x20
	iret

key_lookup:
	db 0,0,'1234567890-=',127,9,'qwertyuiop[]',10,0
	db 'asdfghjkl;',39,'`',0,'\zxcvbnm,./',0,'*',0,' ',0,0,0,0,0,0
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db 0,0,'!@#$%^&*()_+',127,9,'QWERTYUIOP{}',10,0
	db 'ASDFGHJKL:',39,'~',0,'|ZXCVBNM<>?',0,'*',0,' ',0,0,0,0,0,0
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

window_description:
	wnd_start 'Text Editor', window_callback, window_sz, 450, 280, wnd_flag_scrolled, window_menubar
	add_scrollbars
	add_custom 2, -18, 2, -18, id_textbox, wnd_item_flag_grow_r | wnd_item_flag_grow_b, 'Textbox'
	wnd_end

window_menubar:
	menu_start
	add_menu 'File',window_menu_file,0
	add_menu 'Edit',window_menu_edit,0
	menu_end
window_menu_file:
	menu_start
	add_menu 'New',command_new,0
	add_menu 'Open...',command_open,0
	add_menu 'Save',command_save,0
	add_menu 'Save As...',command_save_as,0
	menu_end
window_menu_edit:
	menu_start
	add_menu 'Cut',command_cut,0
	add_menu 'Copy',command_copy,0
	add_menu 'Paste',command_paste,0
	add_menu 'Delete',command_delete,0
	add_menu '',0,menu_flag_separator
	add_menu 'Select All',command_select_all,0
	menu_end

out_rect: dw 0,0,0,0
redraw_what: dw 0
redraw_line: dw 0
caret_rect: dw 0,0,0,0
