[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

id_ok          equ 1
id_push        equ 2
id_two_of_them equ 3
id_custom      equ 4

start:
	mov	ax,window_description
	mov	bx,sys_wnd_create
	int	0x20
	iret

window_callback:
	cmp	cx,msg_btn_clicked
	je	.clicked
	cmp	cx,msg_custom_draw
	je	.draw
	cmp	cx,msg_custom_mouse
	je	.mouse
	cmp	cx,msg_custom_drag
	je	.drag
	iret

	.drag:
	mov	ax,0x1234
	mov	bx,sys_display_word
	int	0x20
	iret

	.mouse:
	cmp	dx,id_custom
	je	.mouse_custom
	iret

	.draw:
	cmp	dx,id_custom
	je	.draw_custom
	iret

	.mouse_custom:
	test	si,1
	jz	.return
	test	si,2
	jz	.r
	add	byte [custom_color],2
	.r:
	dec	byte [custom_color]
	mov	bx,sys_wnd_redraw
	int	0x20
	iret

	.draw_custom:
	push	ds
	mov	cl,[custom_color]
	mov	ds,si
	mov	bx,sys_draw_block
	int	0x20
	mov	bx,sys_draw_frame
	mov	cx,frame_3d_in
	int	0x20
	pop	ds
	iret

	.clicked:
	cmp	dx,id_push
	je	.push
	cmp	dx,id_ok
	je	.ok
	iret

	.ok:
	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	ax,[es:0]
	mov	bx,sys_wnd_destroy
	int	0x20
	iret

	.push:
	mov	ax,alert_description
	mov	bx,sys_wnd_create
	int	0x20
	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	[es:0],ax
	iret

	.return:
	iret

test_file_path: db '38.txt',0
test_file_path_2: db 'invalid.txt',0
test_file_output: times 16 db 0
custom_color: db 0

window_description:
	wnd_start 'Test Application', window_callback, 0, 230, 200
	add_button 10, 100, 10, 35, id_push, 0, 'Push'
	add_custom 10, -10, 80, -10, id_custom, wnd_item_flag_grow_r | wnd_item_flag_grow_b, 'Custom'
	add_button 10, 100, 45, 70, id_two_of_them, 0, 'Two of them'
	wnd_end

alert_description:
	wnd_start 'Alert', window_callback, 2, 200, 100
	add_static 10, 180, 10, 35, 0, 0, 'You clicked the button.'
	add_button 10, 100, 10 + 25, 35 + 25, id_ok, 0, 'OK'
	wnd_end
