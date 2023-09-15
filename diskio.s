sector_size        equ 0x200

disk_buf_sector    equ 0x00 ; 0xFFFF means not in use
disk_buf_drive     equ 0x02
disk_buf_use_order equ 0x03 ; 0 is most recently used
disk_buf_dirty     equ 0x04 ; 1 if being written
disk_buf_header_sz equ 0x10 ; must be multiple of 16
; TODO invalidating buffers after 2 seconds for external disks

dirent_name        equ  0
dirent_attributes  equ 11
dirent_first_sect  equ 12
dirent_size_low    equ 14
dirent_size_high   equ 16
dirent_sz          equ 18
dirents_per_sector equ 28
dirent_name_sz     equ 11

convert_name_to_8_3: ; es:si = cstr; trashes ax, bx, cx, di
	xor	bx,bx
	xor	di,di
	mov	ax,error_bad_name
	.name_loop:
	mov	cl,[es:si + bx]
	cmp	cl,' '
	je	.return
	cmp	cl,0
	je	.pad_to_11
	cmp	cl,'.'
	je	.convert_extension
	cmp	bx,8
	je	.return
	call	.to_lower
	mov	[.name_buf + bx],cl
	inc	bx
	inc	di
	jmp	.name_loop
	.pad_to_11:
	xor	ax,ax
	cmp	di,dirent_name_sz
	je	.return
	mov	byte [.name_buf + di],' '
	inc	di
	jmp	.pad_to_11
	.convert_extension:
	inc	bx
	.pad_before_extension:
	cmp	di,8
	je	.extension_loop
	mov	byte [.name_buf + di],' '
	inc	di
	jmp	.pad_before_extension
	.extension_loop:
	mov	cl,[es:si + bx]
	cmp	cl,' '
	je	.return
	cmp	cl,0
	je	.pad_to_11
	cmp	cl,'.'
	je	.return
	cmp	di,dirent_name_sz
	je	.return
	call	.to_lower
	mov	[.name_buf + di],cl
	inc	bx
	inc	di
	jmp	.extension_loop
	.return:
	ret

	.to_lower:
	cmp	cl,'A'
	jb	.not_upper
	cmp	cl,'Z'
	ja	.not_upper
	add	cl,'a'-'A'
	.not_upper:
	ret

	.name_buf: db '...........',0

fs_next_sector: ; input: ax = sector, dl = drive number; output: ax = sector (0 if error); preserves: dl
	push	bx
	push	dx
	push	es
	push	ax
	mov	al,ah
	xor	ah,ah
	inc	ax
	call	disk_buffers_read
	pop	bx
	mov	ax,0 ; don't affect flags
	jc	.error
	xor	bh,bh
	add	bx,bx
	mov	ax,[es:bx]
	.error:
	pop	es
	pop	dx
	pop	bx
	ret

do_file_open:
	; TODO Recursing into directories.
	; TODO Other disks.
	; TODO When writing, check the file isn't already open.

	push	di
	push	bx
	push	cx
	mov	bx,ds
	mov	es,bx
	push	bx
	xor	bx,bx
	mov	ds,bx

	.convert_name:
	call	convert_name_to_8_3
	or	ax,ax
	jnz	.return

	.find_root_directory_start:
	mov	ax,1
	mov	dl,[system_drive_number]
	call	disk_buffers_read
	mov	ax,error_disk_io
	jc	.return
	xor	bx,bx
	.find_root_directory_start_loop:
	cmp	word [es:bx],0xFFFD
	jne	.found_root_directory_start
	add	bx,2
	cmp	bx,0x200
	mov	ax,error_corrupt
	je	.return
	jmp	.find_root_directory_start_loop
	.found_root_directory_start:
	shr	bx,1
	mov	[.current_sector],bx

	.scan_root_directory:
	mov	ax,[.current_sector]
	mov	dl,[system_drive_number]
	call	disk_buffers_read
	mov	ax,error_disk_io
	jc	.return
	mov	ax,[es:0x1F8]
	cmp	ax,'k' | ('1' << 8)
	mov	ax,error_corrupt
	jne	.return
	xor	bx,bx
	.scan_directory_entry:
	mov	al,[es:bx + dirent_attributes]
	test	al,1
	jz	.scan_next_entry
	mov	cx,dirent_name_sz
	mov	di,bx
	mov	si,convert_name_to_8_3.name_buf
	rep	cmpsb
	je	.match_found
	.scan_next_entry:
	add	bx,dirent_sz
	cmp	bx,dirent_sz * dirents_per_sector
	jne	.scan_directory_entry
	.scan_next_sector:
	mov	ax,[.current_sector]
	mov	dl,[system_drive_number]
	call	fs_next_sector
	or	ax,ax
	jz	.error_next_disk_io
	cmp	ax,0xFFFE
	je	.error_next_not_found
	cmp	ax,0xF000
	ja	.error_next_corrupt
	mov	[.current_sector],ax
	jmp	.scan_root_directory
	.error_next_disk_io:
	mov	ax,error_disk_io
	jmp	.return
	.error_next_not_found:
	mov	ax,error_not_found
	jmp	.return
	.error_next_corrupt:
	mov	ax,error_not_found
	jmp	.return

	.match_found:
	mov	cl,[system_drive_number] ; read before changing ds
	mov	dx,[.current_sector] ; read before changing ds
	mov	ax,(file_ctrl_sz + 15) / 16
	push	bx
	mov	bx,sys_heap_alloc
	int	0x20
	pop	bx
	mov	di,ax
	mov	ax,error_no_memory
	or	di,di
	jz	.return
	mov	ds,di
	mov	ax,[es:bx + dirent_first_sect]
	mov	[file_ctrl_first_sector],ax
	mov	[file_ctrl_curr_sector],ax
	xor	ax,ax
	mov	[file_ctrl_off_in_sect],ax
	mov	[file_ctrl_dirent_sect],dx
	mov	ax,[es:bx + dirent_size_low]
	mov	[file_ctrl_size_low],ax
	mov	ax,[es:bx + dirent_size_high]
	mov	[file_ctrl_size_high],ax
	mov	[file_ctrl_drive],cl
	mov	ax,bx
	mov	cl,dirent_sz
	div	cl
	mov	[file_ctrl_dirent_index],al
	xor	al,al
	mov	[file_ctrl_mode],al
	xor	ax,ax
	mov	dx,ds
	.return:
	pop	ds
	pop	cx
	pop	bx
	pop	di
	iret

	.current_sector: dw 0

do_file_read:
	push	dx
	push	si
	push	bx
	push	es
	mov	bx,ds
	push	bx
	xor	ax,ax
	mov	ds,ax
	mov	[.target_segment],bx

	.main_loop:
	mov	ax,error_none
	or	cx,cx
	jz	.return
	mov	es,dx
	mov	ax,[es:file_ctrl_curr_sector]
	or	ax,ax
	jz	.next_sector_error_io
	cmp	ax,0xF000
	ja	.next_sector_error_corrupt
	mov	ax,[es:file_ctrl_size_high]
	or	ax,ax
	jnz	.compute_bytes_to_read_from_sector
	mov	ax,[es:file_ctrl_size_low]
	or	ax,ax
	jnz	.compute_bytes_to_read_from_sector
	mov	ax,error_eof
	jmp	.return

	.compute_bytes_to_read_from_sector:
	mov	ax,0x200
	sub	ax,[es:file_ctrl_off_in_sect]
	or	ax,ax
	jz	.next_sector
	cmp	cx,ax
	ja	.c1
	mov	ax,cx
	.c1:
	mov	bx,[es:file_ctrl_size_high]
	or	bx,bx
	jnz	.c2
	mov	bx,[es:file_ctrl_size_low]
	cmp	bx,ax
	ja	.c2
	mov	ax,bx
	.c2:

	.update_file_ctrl:
	add	[es:file_ctrl_off_in_sect],ax
	sub	[es:file_ctrl_size_low],ax
	sbb	word [es:file_ctrl_size_high],0

	.get_buffer:
	push	ax
	push	es
	mov	ax,[es:file_ctrl_curr_sector]
	mov	dl,[es:file_ctrl_drive]
	call	disk_buffers_read
	pop	dx
	pop	bx
	mov	ax,error_disk_io
	jc	.return

	.transfer_bytes:
	xchg	bx,cx
	mov	ax,es
	mov	si,[.target_segment]
	mov	es,si
	mov	ds,ax
	xor	si,si
	push	cx
	rep	movsb
	mov	cx,bx
	pop	bx
	xor	ax,ax
	mov	ds,ax
	sub	cx,bx
	mov	di,si
	jmp	.main_loop

	.next_sector:
	mov	word [es:file_ctrl_off_in_sect],0
	mov	ax,[es:file_ctrl_curr_sector]
	mov	dl,[es:file_ctrl_drive]
	call 	fs_next_sector
	mov	[es:file_ctrl_curr_sector],ax
	or	ax,ax
	jz	.next_sector_error_io
	cmp	ax,0xF000
	ja	.next_sector_error_corrupt
	jmp	.compute_bytes_to_read_from_sector
	.next_sector_error_io:
	mov	ax,error_disk_io
	jmp	.return
	.next_sector_error_corrupt:
	mov	ax,error_corrupt
	jmp	.return

	.return:
	pop	ds
	pop	es
	pop	bx
	pop	si
	pop	dx
	iret

	.target_segment: dw 0

do_file_close:
	push	ax
	push	bx
	mov	ax,dx
	mov	bx,sys_heap_free
	int	0x20
	pop	bx
	pop	ax
	iret

disk_read_sector: ; input: ax = sector, bx = destination / 16, dl = device; output: cf = error
	; TODO Reading the disk geometry.
	push	bp
	push	di
	push	si
	push	dx
	push	cx
	mov	cx,es
	push	cx
	mov	cx,4 ; retry count
	.retry:
	push	dx
	push	cx
	push	bx
	push	ax
	mov	es,bx
	dec	cx
	jz	.error
	div	byte [.sectors_per_track]
	mov	cl,ah
	inc	cl
	xor	ah,ah
	div	byte [.heads_per_cylinder]
	mov	dh,ah
	mov	ch,al
	mov	ax,0x0201
	xor	bx,bx
	clc
	int	0x13
	pop	ax
	pop	bx
	pop	cx
	pop	dx
	jc	.retry
	pop	cx
	mov	es,cx
	clc
	.return:
	pop	cx
	pop	dx
	pop	si
	pop	di
	pop	bp
	ret
	.error:
	stc
	jmp	.return
	.sectors_per_track: db 9
	.heads_per_cylinder: db 2

disk_buffers_read: ; input: ax = sector, dl = drive number; output: es = segment, cf = error
	push	bx
	push	cx
	push	dx

	mov	bx,[disk_buffer_segment]
	mov	es,bx
	xor	ch,ch
	mov	cl,[disk_buffer_count]
	.find_loop:
	cmp	[es:disk_buf_sector],ax
	jne	.find_loop_next
	cmp	[es:disk_buf_drive],dl
	jne	.find_loop_next
	jmp	.match
	.find_loop_next:
	add	bx,(sector_size + disk_buf_header_sz) / 16
	mov	es,bx
	loop	.find_loop

	mov	bx,[disk_buffer_segment]
	mov	es,bx
	xor	ch,ch
	mov	cl,[disk_buffer_count]
	mov	dh,cl
	.evict_loop:
	cmp	[es:disk_buf_use_order],dh
	je	.write_back
	add	bx,(sector_size + disk_buf_header_sz) / 16
	mov	es,bx
	loop	.evict_loop
	jmp	exception_handler

	.write_back:
	cmp	byte [es:disk_buf_dirty],1
	je	$ ; TODO Write back.
	.read_into:
	add	bx,disk_buf_header_sz / 16
	call	disk_read_sector
	jc	.error
	mov	[es:disk_buf_sector],ax
	mov	[es:disk_buf_drive],dl
	mov	byte [es:disk_buf_dirty],0
	sub	bx,disk_buf_header_sz / 16
	.match:
	mov	al,byte [es:disk_buf_use_order]
	mov	byte [es:disk_buf_use_order],0
	xor	ch,ch
	mov	cl,[disk_buffer_count]
	push	bx
	mov	bx,[disk_buffer_segment]
	.update_lru:
	mov	es,bx
	cmp	[es:disk_buf_use_order],al
	jae	.update_lru_next
	inc	byte [es:disk_buf_use_order]
	.update_lru_next:
	add	bx,(sector_size + disk_buf_header_sz) / 16
	loop	.update_lru
	pop	bx
	add	bx,disk_buf_header_sz / 16
	mov	es,bx
	clc
	.return:
	pop	dx
	pop	cx
	pop	bx
	ret

	.error:
	stc
	jmp	.return

disk_buffers_alloc:
	int	0x12
	cmp	ax,100
	jb	out_of_memory_error
	mov	bl,32
	div	bl
	mov	[disk_buffer_count],al
	xor	ah,ah
	mov	bx,(sector_size + disk_buf_header_sz) / 16
	mul	bx
	mov	bx,sys_heap_alloc
	int	0x20
	jc	out_of_memory_error
	mov	[disk_buffer_segment],ax
	xor	ch,ch
	mov	cl,[disk_buffer_count]
	mov	dh,cl
	mov	bx,0xFFFF
	.init_buf_loop:
	mov	es,ax
	mov	[es:disk_buf_sector],bx
	mov	[es:disk_buf_use_order],dh
	add	ax,(sector_size + disk_buf_header_sz) / 16
	loop	.init_buf_loop
	ret

do_diskio_syscall:
	or	bl,bl
	jz	do_file_open
	dec	bl
	jz	do_file_close
	dec	bl
	jz	do_file_read
	jmp	exception_handler

system_drive_number: db 0
disk_buffer_count:   db 0
disk_buffer_segment: dw 0
