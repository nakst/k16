[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

id_file_list equ 0x0001

start:
	mov	ax,fm_window_description
	mov	bx,sys_wnd_create
	int	0x20

	mov	si,.test_exe
	mov	bx,sys_app_start
	int	0x20

	iret

	.test_exe: db 'test.exe',0

class_file_list:
	.dispatch:
	cmp	cx,msg_custom_draw
	je	.on_draw
	iret

	.on_draw:
	push	ds
	mov	ds,si
	mov	cl,0x0F
	mov	bx,sys_draw_block
	int	0x20
	mov	cx,frame_3d_in
	mov	bx,sys_draw_frame
	int	0x20
	pop	ds
	iret

fm_window_callback:
	cmp	dx,id_file_list
	je	class_file_list.dispatch
	iret

fm_window_description:
	wnd_start 'File Manager', fm_window_callback, 0, 250, 200
	add_custom 0, 0, 0, 0, id_file_list, wnd_item_flag_grow_r | wnd_item_flag_grow_b, 'File List'
	wnd_end
