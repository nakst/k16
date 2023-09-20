[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

id_file_list equ 0x0001

fm_window_listing equ 0x00
fm_window_lcount  equ 0x02
fm_window_sz      equ 0x04

max_lcount equ 128 ; no more than 128 items in a folder

start:
	mov	si,.test_exe
	mov	bx,sys_app_start
	int	0x20

	mov	si,.test_directory
	call	open_fm_window

	iret

	.test_exe: db 's:test.exe',0
	.test_directory: db 's',0

open_fm_window: ; si = directory
	mov	ax,(32 * max_lcount) / 16 ; TODO Resizing.
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jz	.listing_memory_alloc_failed
	mov	[.listing],ax

	mov	al,open_access_directory
	mov	bx,sys_file_open
	int	0x20
	or	ax,ax
	jnz	.open_directory_failed
	mov	[.directory],dx

	mov	cx,max_lcount
	push	ds
	mov	dx,[.directory]
	mov	ds,[.listing]
	mov	bx,sys_dir_read
	xor	di,di
	int	0x20
	pop	ds
	or	ax,ax
	jnz	.read_directory_failed
	mov	[.lcount],cx

	mov	dx,[.directory]
	mov	bx,sys_file_close
	int	0x20

	mov	ax,fm_window_description
	mov	bx,sys_wnd_create
	int	0x20
	or	ax,ax
	jz	.window_create_failed
	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	bx,[.listing]
	mov	[es:fm_window_listing],bx
	mov	bx,[.lcount]
	mov	[es:fm_window_lcount],bx

	mov	bx,sys_wnd_redraw
	mov	dx,id_file_list
	int	0x20

	ret

	.window_create_failed:
	mov	ax,[.listing]
	mov	bx,sys_heap_free
	int	0x20
	.listing_memory_alloc_failed:
	mov	ax,error_no_memory
	mov	bx,sys_alert_error
	int	0x20
	ret

	.read_directory_failed:
	mov	dx,[.directory]
	mov	bx,sys_file_close
	int	0x20
	.open_directory_failed:
	push	ax
	mov	ax,[.listing]
	mov	bx,sys_heap_free
	int	0x20
	pop	ax
	mov	bx,sys_alert_error
	int	0x20
	ret

	.listing: dw 0
	.lcount: dw 0
	.directory: dw 0

class_file_list:
	.dispatch:
	cmp	cx,msg_custom_draw
	je	.on_draw
	iret

	.on_draw:
	push	ax
	mov	es,si
	mov	ax,[es:di + rect_l]
	mov	[.rect + rect_l],ax
	mov	ax,[es:di + rect_r]
	mov	[.rect + rect_r],ax
	mov	ax,[es:di + rect_t]
	mov	[.rect + rect_t],ax
	mov	ax,[es:di + rect_b]
	mov	[.rect + rect_b],ax
	mov	di,.rect
	mov	cl,0x0F
	mov	bx,sys_draw_block
	int	0x20
	mov	cx,frame_3d_in
	mov	bx,sys_draw_frame
	int	0x20
	pop	ax
	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	ax,[es:fm_window_listing]
	or	ax,ax
	jz	.return
	mov	cx,[es:fm_window_lcount]
	mov	es,ax
	xor	si,si
	mov	dx,[.rect + rect_t]
	add	dx,12
	.draw_item_loop:
	push	cx
	push	ds
	mov	cx,[.rect + rect_l]
	add	cx,5
	mov	bx,sys_draw_text
	mov	ax,es
	mov	ds,ax
	xor	ax,ax
	int	0x20 ; TODO Zero-terminate. Check the present attribute bit.
	pop	ds
	pop	cx
	add	si,dirent_sz
	add	dx,12
	loop	.draw_item_loop
	.return:
	iret

	.rect: dw 0,0,0,0

fm_window_callback:
	cmp	dx,id_file_list
	je	class_file_list.dispatch
	iret

fm_window_description:
	wnd_start 'File Manager', fm_window_callback, fm_window_sz, 250, 200
	add_custom 0, 0, 0, 0, id_file_list, wnd_item_flag_grow_r | wnd_item_flag_grow_b, 'File List'
	wnd_end
