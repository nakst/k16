[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

id_file_list equ 0x0001

fm_window_listing equ 0x00
fm_window_lcount  equ 0x02
fm_window_sz      equ 0x04

fm_command_new_folder equ 0x0001
fm_command_open       equ 0x0002
fm_command_get_info   equ 0x0003
fm_command_delete     equ 0x0004

max_lcount equ 128 ; no more than 128 items in a folder

start:
	mov	si,.test_directory
	call	open_fm_window

	iret

	.test_directory: db 's',0
	.test_path_buffer: db 's:                    ',0

lookup_icon: ; input: es:si = directory entry; output: ax = icon; trashes: everything except ds, es, si
	mov	bx,si
	add	bx,dirent_name_sz
	xor	cx,cx
	.look_for_dot_loop:
	mov	al,[es:bx - 1]
	cmp	al,'.'
	je	.found_dot
	dec	bx
	or	al,al
	jz	.look_for_dot_loop
	inc	cx
	cmp	bx,si
	jne	.look_for_dot_loop
	.found_dot:
	mov	ax,icons + 0x200 * 0
	cmp	cx,3
	jne	.return

%macro check_extension 4
	cmp	byte [es:bx + 0],%2
	jne	.not_%1
	cmp	byte [es:bx + 1],%3
	jne	.not_%1
	cmp	byte [es:bx + 2],%4
	jne	.not_%1
	mov	ax,icons + 0x200 * %1
	jmp	.return
	.not_%1:
%endmacro

icon_system_file equ 1
icon_executable  equ 2

	check_extension icon_system_file,'s','y','s'
	check_extension icon_executable, 'e','x','e'
	
	.return:
	ret

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
	mov	bx,sys_wnd_show
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
	cmp	cx,msg_custom_mouse
	je	.on_mouse
	iret

	.on_mouse:
	cmp	si,1
	jne	.return
	mov	di,.rect
	mov	bx,sys_wnd_get_rect
	int	0x20
	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	ax,[es:fm_window_listing]
	or	ax,ax
	jz	.return
	mov	cx,[es:fm_window_lcount]
	mov	es,ax
	xor	si,si
	.mouse_item_loop:
	push	cx
	test	byte [es:si + dirent_attributes],dentry_attr_present
	jz	.no_hit
	mov	bx,[es:si + dirent_x_position]
	add	bx,[.rect + rect_l]
	mov	[.itemrect + rect_l],bx
	add	bx,0x20
	mov	[.itemrect + rect_r],bx
	mov	bx,[es:si + dirent_y_position]
	add	bx,[.rect + rect_t]
	mov	[.itemrect + rect_t],bx
	add	bx,0x20
	mov	[.itemrect + rect_b],bx
	mov	bx,sys_cursor_get
	int	0x20
	cmp	cx,[.itemrect + rect_l]
	jl	.no_hit
	cmp	cx,[.itemrect + rect_r]
	jge	.no_hit
	cmp	dx,[.itemrect + rect_t]
	jl	.no_hit
	cmp	dx,[.itemrect + rect_b]
	jl	.hit
	.no_hit:
	pop	cx
	add	si,dirent_sz
	dec	cx
	jnz	.mouse_item_loop
	iret
	.hit:
	pop	cx
	call	lookup_icon
	cmp	ax,icons + 0x200 * icon_executable
	je	.hit_executable
	iret
	.hit_executable:
	mov	cx,dirent_name_sz
	mov	di,start.test_path_buffer + 2
	.copy_name:
	mov	al,[es:si]
	mov	[di],al
	inc	si
	inc	di
	loop	.copy_name
	mov	si,start.test_path_buffer
	mov	bx,sys_app_start
	int	0x20
	or	ax,ax
	jz	.return
	mov	bx,sys_alert_error
	int	0x20
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
	pop	ax
	mov	bx,sys_wnd_get_extra
	int	0x20
	mov	ax,[es:fm_window_listing]
	or	ax,ax
	jz	.return
	mov	cx,[es:fm_window_lcount]
	mov	es,ax
	xor	si,si
	; TODO Clipping.
	.draw_item_loop:
	push	cx
	test	byte [es:si + dirent_attributes],dentry_attr_present
	jz	.skip_item

	mov	cx,[es:si + dirent_x_position]
	add	cx,[.rect + rect_l]
	mov	[.itemrect + rect_l],cx
	add	cx,0x20
	mov	[.itemrect + rect_r],cx
	mov	cx,[es:si + dirent_y_position]
	add	cx,[.rect + rect_t]
	mov	[.itemrect + rect_t],cx
	add	cx,0x20
	mov	[.itemrect + rect_b],cx

	call	lookup_icon
	push	si
	mov	si,ax
	mov	di,iconrect
	mov	ax,0x20
	mov	cx,[.itemrect + rect_l]
	mov	dx,[.itemrect + rect_t]
	mov	bx,sys_draw_icon
	int	0x20
	pop	si

	push	ds
	push	es
	mov	ax,ds
	mov	bx,es
	mov	ds,bx
	mov	es,ax
	mov	di,.mstrrect
	mov	bx,sys_measure_text
	xor	al,al
	int	0x20
	mov	bx,sys_draw_text
	xor	ax,ax
	mov	cx,[es:.itemrect + rect_l]
	add	cx,[es:.itemrect + rect_r]
	sub	cx,[es:.mstrrect + rect_r]
	shr	cx,1
	mov	dx,[es:.itemrect + rect_b]
	sub	dx,[es:.mstrrect + rect_t]
	inc	dx
	mov	di,[dirent_name_sz]
	mov	byte [dirent_name_sz],0
	int	0x20
	mov	[dirent_name_sz],di
	pop	es
	pop	ds
	.skip_item:
	pop	cx
	add	si,dirent_sz
	dec	cx
	jnz	.draw_item_loop
	jmp	.return

	.return:
	iret

	.rect: dw 0,0,0,0
	.itemrect: dw 0,0,0,0
	.mstrrect: dw 0,0,0,0

fm_window_callback:
	cmp	cx,msg_menu_command
	je	.menu_command
	cmp	dx,id_file_list
	je	class_file_list.dispatch
	iret

	.menu_command:
	cmp	dx,menu_command_close
	je	.close
	iret

	.close:
	mov	bx,sys_wnd_get_extra
	int	0x20
	push	ax
	mov	ax,[es:fm_window_listing]
	mov	bx,sys_heap_free
	int	0x20
	pop	ax
	mov	bx,sys_wnd_destroy
	int	0x20
	iret

fm_window_description:
	wnd_start 'File Manager', fm_window_callback, fm_window_sz, 250, 200, wnd_flag_scrolled, fm_window_menubar
	add_scrollbars
	add_custom 2, -18, 2, -18, id_file_list, wnd_item_flag_grow_r | wnd_item_flag_grow_b, 'File List'
	wnd_end

fm_window_menubar:
	menu_start
	add_menu 'File',fm_window_menu_file,0
	add_menu 'Edit',fm_window_menu_edit,0
	menu_end
fm_window_menu_file:
	menu_start
	add_menu 'New Folder',fm_command_new_folder,0
	add_menu '',0,menu_flag_separator
	add_menu 'Open',fm_command_open,0
	add_menu 'Get Info',fm_command_get_info,0
	menu_end
fm_window_menu_edit:
	menu_start
	add_menu 'Delete',fm_command_delete,0
	menu_end

%include "bin/icons.s"
iconrect: dw 0,0x20,0,0x20
