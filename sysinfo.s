[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

value_first  equ 1
id_free_mem  equ 1
id_used_mem  equ 2
id_total_mem equ 3
value_count  equ 3

id_refresh   equ 100

start:
	cmp	byte [single_instance],1
	je	.return
	mov	byte [single_instance],1
	call	get_values
	mov	ax,window_description
	mov	bx,sys_wnd_create
	int	0x20
	mov	bx,sys_wnd_show
	int	0x20
	.return:
	iret

get_values:
	mov	ax,info_index_free_memory
	mov	bx,sys_info_read
	int	0x20
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	[value_array + id_free_mem * 2 - value_first * 2],ax
	mov	cx,ax

	mov	ax,info_index_total_memory
	mov	bx,sys_info_read
	int	0x20
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	[value_array + id_total_mem * 2 - value_first * 2],ax

	sub	ax,cx
	mov	[value_array + id_used_mem * 2 - value_first * 2],ax

	ret

window_callback:
	cmp	cx,msg_menu_command
	je	.menu_command
	cmp	cx,msg_number_get
	je	.number_get
	cmp	cx,msg_btn_clicked
	je	.btn_clicked
	iret

	.btn_clicked:
	cmp	dx,id_refresh
	je	.refresh
	iret

	.refresh:
	push	ax
	call	get_values
	pop	ax
	mov	dx,value_first - 1
	.refresh_loop:
	inc	dx
	mov	bx,sys_wnd_redraw
	int	0x20
	cmp	dx,value_count
	jne	.refresh_loop
	iret

	.number_get:
	mov	es,si
	sub	dx,value_first
	mov	bx,dx
	shl	bx,1
	mov	ax,[value_array + bx]
	mov	[es:di],ax
	iret

	.menu_command:
	cmp	dx,menu_command_close
	je	.close
	iret

	.close:
	mov	byte [single_instance],0
	mov	bx,sys_wnd_destroy
	int	0x20
	iret

window_description:
	wnd_start 'System Information', window_callback, 0, 200, 150, wnd_flag_dialog, window_menubar
	add_static 15, 180, 10+15*0, 10+15*1, 0, wnd_item_flag_bold, 'Memory'
	add_static 15+20*1, 100, 10+15*1, 10+15*2, 0, 0, 'Free (K):'
	add_static 15+20*1, 100, 10+15*2, 10+15*3, 0, 0, 'Used (K):'
	add_static 15+20*1, 100, 10+15*3, 10+15*4, 0, 0, 'Total (K):'
	add_number 100, 160, 10+15*1, 10+15*2, id_free_mem, 0, ''
	add_number 100, 160, 10+15*2, 10+15*3, id_used_mem, 0, ''
	add_number 100, 160, 10+15*3, 10+15*4, id_total_mem, 0, ''
	add_button 15, 95, 88, 111, id_refresh, 0, 'Refresh'
	wnd_end

window_menubar:
	menu_start
	menu_end

single_instance: db 0
value_array: times value_count dw 0
