[bits 16]
[org 0x0500]
[cpu 8086]

%include "syscall.h"

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
	call	disk_buffers_alloc
	call	mouse_setup
	call	gfx_setup
	call	wndmgr_setup

	mov	si,.desktop_path
	mov	bx,sys_app_start
	int	0x20
	or	ax,ax
	jz	wndmgr_event_loop
	cmp	ax,error_no_memory
	je	.no_memory
	mov	ax,.desktop_load_error
	mov	bx,sys_wnd_create
	int	0x20
	jmp	wndmgr_event_loop
	.no_memory:
	mov	ax,error_no_memory
	mov	bx,sys_alert_error
	int	0x20
	jmp	wndmgr_event_loop

	.desktop_path: db 's:desktop.sys',0
	.desktop_load_error:
		wnd_start 'System Error', .desktop_load_error_callback, 0, 200, 100
		add_static 10, 180, 10, 35, 0, 0, 'Missing system file "desktop.exe".'
		add_static 10, 100, 35, 60, 0, 0, 'Please restart your computer.'
		wnd_end
	.desktop_load_error_callback: iret

%include "heap.s"
%include "diskio.s"
%include "gfx.s"
%include "mouse.s"
%include "wndmgr.s"

do_app_start:
	push	dx
	mov	al,open_access_read
	mov	bx,sys_file_open
	int	0x20
	or	ax,ax
	jz	.opened
	pop	dx
	iret

	.opened:
	push	es
	mov	es,dx
	mov	ax,[es:file_ctrl_size_high]
	or	ax,ax
	jz	.not_too_large
	mov	ax,error_too_large
	pop	es
	pop	dx
	iret

	.not_too_large:
	mov	ax,[es:file_ctrl_size_low]
	add	ax,15
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jnz	.allocated
	mov	ax,error_no_memory
	pop	es
	pop	dx
	iret

	.allocated:
	mov	si,ax ; si = segment
	push	cx
	push	di
	push	ds
	xor	di,di
	mov	ds,ax
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
	iret

	.read_done:
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
	mov	ds,si
	push	si
	xor	ax,ax
	push	ax
	iret

	.after:
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

do_misc_syscall:
	or	bl,bl
	jz	do_display_word
	dec	bl
	jz	do_app_start
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
