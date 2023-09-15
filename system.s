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
	mov	sp,0x100
	sti
	add	ax,0x10 ; 256 bytes
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
	call	gfx_setup
	call	mouse_setup
	call	wndmgr_setup

	mov	si,.test_file_path
	mov	al,open_access_read
	mov	bx,sys_file_open
	int	0x20
	mov	es,dx
	; TODO Check high size is 0.
	mov	ax,[es:file_ctrl_size_low]
	add	ax,15
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	bx,sys_heap_alloc
	int	0x20
	xor	di,di
	mov	[.test_segment],ax
	mov	ds,ax
	mov	cx,[es:file_ctrl_size_low]
	mov	bx,sys_file_read
	int	0x20
	mov	bx,sys_file_close
	int	0x20
	xor	ax,ax
	mov	ds,ax

	pushf
	mov	ax,[.test_segment]
	mov	ds,ax
	push	ax
	xor	ax,ax
	push	ax
	iret

	jmp	$

	.test_file_path: db 'test.exe',0
	.test_segment: dw 0

%include "heap.s"
%include "diskio.s"
%include "gfx.s"
%include "mouse.s"
%include "wndmgr.s"

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

int_0x20:
	cld
	sti
	or	bh,bh
	jz	do_display_word
	dec	bh
	jz	do_heap_syscall
	dec	bh
	jz	do_diskio_syscall
	dec	bh
	jz	do_gfx_syscall
	dec	bh
	jz	do_wndmgr_syscall
	jmp	exception_handler
