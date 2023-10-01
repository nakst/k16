[bits 16]
[org 0x0500]
[cpu 8086]

%include "syscall.h"

module_code equ 0x00
module_path equ 0x02
module_refs equ 0x04
module_sz   equ 0x10 ; must be a multiple of 16

; dl = drive number, bx = end of system / 16, cs = ds = ss = 0, sp = 0x7C00, direction flag clear, interrupts enabled
start:
	.save_boot_information:
	mov	[system_drive_number],dl
	mov	[heap_start],bx

	.allocate_stack:
	mov	ax,[heap_start]
	cli
	mov	ss,ax
	mov	sp,0x200
	sti
	add	ax,0x20 ; 512 bytes
	mov	[heap_start],ax

	.write_ivt:
	mov	bx,exception_handler
	xor	ax,ax
	mov	[ 0],bx
	mov	[ 2],ax
	mov	[ 4],bx
	mov	[ 6],ax
	mov	[ 8],bx
	mov	[10],ax
	mov	[12],bx
	mov	[14],ax
	mov	[16],bx
	mov	[18],ax
	mov	[20],bx
	mov	[22],ax
	mov	[24],bx
	mov	[26],ax
	mov	[28],bx
	mov	[30],ax
	mov	bx,int_0x20
	mov	[0x20 * 4 + 0x00],bx
	mov	[0x20 * 4 + 0x02],ax

	call	heap_setup
	call	diskio_setup
	call	mouse_setup
	call	keybrd_setup
	call	gfx_setup
	call	wndmgr_setup

	call	dll_alloc
	jc	out_of_memory_error
	mov	[module_list],ax

	mov	si,.desktop_path
	mov	bx,sys_app_start
	int	0x20
	or	ax,ax
	jz	wndmgr_event_loop
	cmp	ax,error_not_found
	jne	.general_error
	mov	ax,.desktop_load_error
	mov	bx,sys_wnd_create
	int	0x20
	mov	bx,sys_wnd_show
	int	0x20
	jmp	wndmgr_event_loop
	.general_error:
	mov	bx,sys_alert_error
	int	0x20
	jmp	wndmgr_event_loop

	.desktop_path: db 's:',FIRST_APPLICATION,0
	.desktop_load_error:
		wnd_start 'System Error', do_alert_error.callback, 0, 200, 100, wnd_flag_dialog, 0
		add_static 10, 180, 10, 35, 0, 0, 'Missing system file "desktop.exe".'
		add_static 10, 100, 35, 60, 0, 0, 'Please restart your computer.'
		wnd_end

%include "heap.s"
%include "diskio.s"
%include "gfx.s"
%include "mouse.s"
%include "keybrd.s"
%include "wndmgr.s"

module_free: ; input: ax = module
	push	bx
	call	dll_remove
	mov	bx,sys_heap_free
	int	0x20
	pop	bx
	ret

do_app_start:
	push	es
	push	si
	push	di
	xor	ax,ax
	mov	es,ax
	mov	ax,[es:module_list]
	push	si
	push	ax
	.module_search:
	pop	ax
	pop	si
	call	dll_next
	call	dll_is_list
	jc	.not_found
	push	si
	push	ax
	mov	es,ax
	mov	bx,[es:module_path]
	mov	es,bx
	xor	di,di
	.compare_paths:
	cmpsb
	jne	.module_search
	dec	si
	lodsb
	or	al,al
	jnz	.compare_paths
	pop	ax
	pop	si
	mov	es,ax
	inc	word [es:module_refs]
	pop	di
	pop	si
	pop	es
	mov	si,ax
	jmp	.call_start
	.not_found:
	pop	di
	pop	si
	pop	es

	.open_file:
	push	dx
	mov	al,open_access_read
	mov	bx,sys_file_open
	push	si
	int	0x20
	pop	si
	or	ax,ax
	jz	.opened
	pop	dx
	iret

	.opened:
	push	es
	mov	es,dx
	mov	ax,[es:file_ctrl_size_high]
	or	ax,ax
	jnz	.too_large
	mov	ax,[es:file_ctrl_size_low]
	cmp	ax,0xFC00 ; ensure there's some space for module metadata
	jae	.too_large
	add	ax,15
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	add	ax,module_sz / 16

	push	si
	push	cx
	push	ax
	xor	cx,cx
	.count_path_bytes:
	inc	cx
	cmp	cx,0x100
	je	.name_too_long
	lodsb
	or	al,al
	jnz	.count_path_bytes
	add	cx,15
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	pop	ax
	add	ax,cx
	pop	cx
	pop	si
	jmp	.allocate
	.name_too_long:
	pop	ax
	pop	cx
	pop	si
	pop	es
	pop	dx
	mov	ax,error_bad_name
	iret

	.allocate:
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jnz	.allocated
	mov	ax,error_no_memory
	pop	es
	pop	dx
	iret

	.too_large:
	mov	ax,error_too_large
	pop	es
	pop	dx
	iret

	.allocated:
	push	es
	push	ax
	mov	cx,[es:file_ctrl_size_low]
	mov	es,ax
	add	ax,module_sz / 16
	mov	[es:module_code],ax
	add	cx,15
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	add	ax,cx
	mov	[es:module_path],ax
	mov	word [es:module_refs],1
	mov	es,ax
	push	di
	xor	di,di
	.copy_path_loop:
	lodsb
	stosb
	or	al,al
	jnz	.copy_path_loop
	pop	di
	pop	ax
	pop	es
	mov	si,ax ; si = segment
	push	cx
	push	di
	push	ds
	mov	ds,ax
	mov	di,module_sz
	mov	cx,[es:file_ctrl_size_low]
	mov	bx,sys_file_read
	int	0x20
	mov	bx,sys_file_close
	int	0x20
	pop	ds
	pop	di
	pop	cx
	pop	es
	pop	dx
	or	ax,ax
	jz	.read_done
	push	ax
	mov	ax,si
	mov	bx,sys_heap_free
	int	0x20
	pop	ax
	iret

	.read_done:
	push	ds
	xor	ax,ax
	mov	ds,ax
	mov	bx,si
	mov	ax,[module_list]
	call	dll_insert_end
	pop	ds

	.call_start:
	push	cx
	push	dx
	push	di
	push	bp
	push	ds
	push	es
	pushf
	xor	ax,ax
	push	ax
	mov	ax,.after
	push	ax
	pushf
	add	si,module_sz / 16
	mov	ds,si
	push	si
	xor	ax,ax
	push	ax
	iret

	.after:
	mov	ax,ds
	sub	ax,module_sz / 16
	mov	es,ax
	dec	word [es:module_refs]
	jnz	.return
	call	module_free
	.return:
	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	dx
	pop	cx
	xor	ax,ax
	iret

exception_handler:
	cli
	xor	ax,ax
	mov	ds,ax
	mov	si,.message
	call	print_cstring
	jmp	$
	.message: db 'Error: A processor exception occurred.',0

; si = pointer to zero-terminated string; trashes ax, si
print_cstring:
	push	bx
	push	cx
	push	dx
	push	bp
	push	di
	mov	bx,7
	.loop:
	lodsb
	or	al,al
	jz	.return
	mov	ah,0xE
	int	0x10
	jmp	.loop
	.return:
	pop	di
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	ret

do_info_read:
	or	ax,ax
	jz	.read_free_memory
	dec	ax
	jz	.read_total_memory
	jmp	exception_handler

	.read_free_memory:
	call	heap_get_free_count
	iret

	.read_total_memory:
	push	ds
	xor	ax,ax
	mov	ds,ax
	mov	ax,[heap_total]
	pop	ds
	iret

do_misc_syscall:
	or	bl,bl
	jz	do_display_word
	dec	bl
	jz	do_app_start
	dec	bl
	jz	do_info_read
	jmp	exception_handler

int_0x20:
	cld
	sti
	or	bh,bh
	jz	do_misc_syscall
	dec	bh
	jz	do_heap_syscall
	dec	bh
	jz	do_diskio_syscall
	dec	bh
	jz	do_gfx_syscall
	dec	bh
	jz	do_wndmgr_syscall
	jmp	exception_handler

module_list: dw 0
