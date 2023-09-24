[bits 16]
[org 0x7C00]
[cpu 8086]

directory_buffer   equ 0x0500 ; 0x0700
system_destination equ 0x0500 ; 0x7500
boot_stack         equ 0x7B00 ; 0x7C00
boot_sector        equ 0x7C00 ; 0x7E00
sector_table       equ 0x7E00 ; 0x8400

%include "syscall.h"

; dl = drive number
start:
	.setup_segments:
	cli
	xor	ax,ax
	mov	ds,ax
	mov	ss,ax
	mov	sp,boot_sector ; put stack below the code
	sti
	cld
	jmp	0x0000:.set_cs
	.set_cs:

	.fill_memory: ; fill all usable memory with 0xC1 to test we're not relying on emulator's zero initialization
	int	0x12
	mov	bx,0x40
	mul	bx
	mov	bx,ax
	.fill_memory_loop:
	dec	bx
	mov	cx,0x10
	mov	es,bx
	xor	di,di
	mov	al,0xC1
	rep	stosb
	cmp	bx,0x50
	je	.fill_memory_done
	cmp	bx,0x7E0
	jne	.fill_memory_loop
	sub	bx,0x20
	jmp	.fill_memory_loop
	.fill_memory_done:

	xor	ax,ax
	mov	bx,sector_table / 16
	.load_sector_table:
	cmp	al,[sector_table_size]
	je	.check_root_directory_non_empty
	inc	ax
	push	ax
	push	bx
	call	read_sector
	pop	bx
	pop	ax
	add	bx,0x200 / 16
	jmp	.load_sector_table

	.check_root_directory_non_empty:
	xor	bh,bh
	mov	bl,[sector_table_size]
	inc	bx
	mov	[current_sector],bx
	add	bx,bx
	mov	ax,[sector_table + bx]
	mov	si,msg_file_system
	cmp	ax,0xFFFF
	je	print_error_message

	.scan_root_directory:
	mov	ax,[current_sector]
	mov	bx,directory_buffer / 16
	call	read_sector
	xor	bx,bx
	mov	es,bx
	mov	bx,directory_buffer
	.scan_directory_entry:
	mov	al,[directory_buffer + dirent_attributes + bx]
	test	al,dentry_attr_present
	jz	.scan_next_entry
	mov	cx,dirent_name_sz
	mov	si,directory_buffer
	add	si,bx
	mov	di,system_name
	rep	cmpsb
	je	.match_found
	.scan_next_entry:
	add	bx,dirent_sz
	cmp	bx,dirent_sz * dirents_per_sector
	jne	.scan_directory_entry
	.scan_next_sector:
	mov	bx,[current_sector]
	add	bx,bx
	mov	ax,[sector_table + bx]
	mov	si,msg_not_found
	cmp	ax,0xFFFE
	je	print_error_message
	mov	[current_sector],ax
	jmp	.scan_root_directory
	.match_found:
	mov	si,msg_too_large
	mov	al,[directory_buffer + dirent_size_high + bx]
	or	al,al
	jnz	print_error_message
	mov	ax,[directory_buffer + dirent_size_low + bx]
	cmp	ax,0x7000
	ja	print_error_message
	mov	ax,[directory_buffer + dirent_first_sect + bx]
	mov	[current_sector],ax

	mov	bx,system_destination / 16
	.load_system:
	push	bx
	call	read_sector
	mov	bx,[current_sector]
	add	bx,bx
	mov	ax,[sector_table + bx]
	pop	bx
	add	bx,0x200 / 16
	cmp	ax,0xFFFE
	je	.start_system
	mov	[current_sector],ax
	jmp	.load_system

	.start_system:
	mov	dl,[drive_number]
	jmp	system_destination

; si = pointer to zero-terminated string
print_error_message:
	lodsb
	cmp	al,1
	je	.common_message
	or	al,al
	jz	$
	mov	ah,0xE
	int	0x10
	jmp	print_error_message
	.common_message:
	mov	si,msg_com_error
	jmp	print_error_message

; ax = sector, bx = destination / 16
read_sector:
	mov	cx,4 ; retry count
	.retry:
	push	cx
	push	bx
	push	ax
	mov	es,bx
	mov	si,msg_disk_read
	dec	cx
	jz	print_error_message
	div	byte [sectors_per_track]
	mov	cl,ah
	inc	cl
	xor	ah,ah
	div	byte [heads_per_cylinder]
	mov	dh,ah
	mov	ch,al
	mov	ax,0x0201
	mov	dl,[drive_number]
	xor	bx,bx
	clc
	int	0x13
	pop	ax
	pop	bx
	pop	cx
	jc	.retry
	ret

msg_disk_read:   db 'Disk read error.',1
msg_file_system: db 'Unknown or corrupt file system.',1
msg_not_found:   db 'Missing k16.sys.',1
msg_too_large:   db 'System too large.',1
msg_com_error:   db 10,13,'Remove the disk and press Ctrl+Alt+Delete.',0
system_name:     db 'k16.sys',0,0,0,0,0,0,0,0,0,0,0,0,0

drive_number:       db 0
sectors_per_track:  db 9
heads_per_cylinder: db 2
current_sector:     dw 0

times (0x1F8 - $ + $$) nop
fs_signature:      db 'k16fs'
sector_table_size: db 3
boot_signature:    dw 0xAA55
