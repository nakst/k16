sector_size        equ 0x200

disk_buf_sector    equ 0x00 ; 0xFFFF means not in use
disk_buf_drive     equ 0x02
disk_buf_use_order equ 0x03 ; 0 is most recently used
disk_buf_dirty     equ 0x04 ; 1 if being written
disk_buf_header_sz equ 0x10 ; must be multiple of 16
; TODO invalidating buffers after 2 seconds for external disks

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
	mov	dx,open_parent_root
	.loop:
	mov	bx,si
	push	ax
	.find_type:
	lodsb
	or	al,al
	jz	.file
	cmp	al,':'
	je	.directory
	jmp	.find_type
	.file:
	pop	ax
	mov	si,bx
	mov	bx,sys_file_open
	jmp	do_file_open_at
	.directory:
	pop	ax
	dec	si
	mov	byte [si],0
	push	si
	mov	si,bx
	push	ax
	mov	al,open_access_directory
	mov	bx,sys_file_open_at
	int	0x20
	pop	bx
	pop	si
	mov	byte [si],':'
	inc	si
	or	ax,ax
	jnz	.error
	mov	ax,bx
	jmp	.loop
	.error:
	iret

do_file_open_at:
	; TODO Other disks (open_parent_root).
	; TODO Check the file isn't already open for exclusive access.

	push	es
	push	di
	push	bx
	push	cx

	xor	bx,bx
	mov	es,bx
	mov	[es:.access_mode],al
	mov	[es:.parent_to_close],dx

	.load_name:
	mov	di,.entry_buf + dirent_name
	mov	cx,dirent_name_sz
	lodsb
	or	al,al
	jz	.bad_name
	.load_name_loop:
	cmp	al,':'
	je	.bad_name
	stosb
	lodsb
	or	al,al
	jz	.load_name_done
	loop	.load_name_loop
	.bad_name:
	push	ds
	mov	ax,error_bad_name
	jmp	.return
	.load_name_done:
	dec	cx
	rep	stosb

	push	ds
	xor	bx,bx
	mov	ds,bx
	cmp	dx,open_parent_root
	je	.at_root
	cmp	dx,0xF000
	jb	.at_directory
	jmp	exception_handler

	.at_root:
	mov	ax,error_not_found ; TODO Parsing disk number.
	mov	bx,[.entry_buf + dirent_name]
	cmp	bx,'s'
	jne	.return
	mov	dl,[.disk_number]
	mov	ax,1
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
	xor	ax,ax
	mov	es,ax
	mov	[.current_sector],ax
	mov	[es:.entry_buf + dirent_first_sect],bx
	mov	[es:.entry_buf + dirent_size_low],ax
	mov	byte [es:.entry_buf + dirent_attributes],dentry_attr_dir | dentry_attr_present
	mov	byte [es:.entry_buf + dirent_size_high],0
	mov	bx,.entry_buf
	jmp	.match_found

	.at_directory:
	mov	es,dx
	mov	bl,[es:file_ctrl_drive]
	mov	[.disk_number],bl
	mov	bx,[es:file_ctrl_first_sector]
	mov	[.current_sector],bx
	.scan_directory:
	mov	ax,[.current_sector]
	mov	dl,[.disk_number]
	call	disk_buffers_read
	mov	ax,error_disk_io
	jc	.return
	xor	bx,bx
	.scan_directory_entry:
	mov	al,[es:bx + dirent_attributes]
	test	al,dentry_attr_present
	jz	.scan_next_entry
	mov	cx,dirent_name_sz
	mov	di,bx
	mov	si,.entry_buf + dirent_name
	rep	cmpsb
	je	.match_found
	.scan_next_entry:
	add	bx,dirent_sz
	cmp	bx,dirent_sz * dirents_per_sector
	jne	.scan_directory_entry
	.scan_next_sector:
	mov	ax,[.current_sector]
	mov	dl,[.disk_number]
	call	fs_next_sector
	or	ax,ax
	jz	.error_next_disk_io
	cmp	ax,0xFFFE
	je	.error_next_not_found
	cmp	ax,0xF000
	ja	.error_next_corrupt
	mov	[.current_sector],ax
	jmp	.scan_directory
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
	mov	ax,error_bad_type
	mov	ch,[.access_mode] ; read before changing ds
	test	byte [es:bx + dirent_attributes],dentry_attr_dir
	jz	.not_directory
	cmp	ch,open_access_directory
	jne	.return
	jmp	.checked_type
	.not_directory:
	cmp	ch,open_access_directory
	je	.return
	.checked_type:
	mov	cl,[.disk_number] ; read before changing ds
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
	xor	ah,ah
	mov	al,[es:bx + dirent_size_high]
	mov	[file_ctrl_size_high],ax
	mov	[file_ctrl_drive],cl
	mov	ax,bx
	mov	cl,dirent_sz
	div	cl
	mov	[file_ctrl_dirent_index],al
	mov	[file_ctrl_mode],ch
	xor	ax,ax
	mov	dx,ds
	mov	ds,ax
	.return:
	push	dx
	mov	dx,[.parent_to_close]
	mov	bx,sys_file_close
	int	0x20
	pop	dx
	pop	ds
	pop	cx
	pop	bx
	pop	di
	pop	es
	iret

	.current_sector: dw 0
	.entry_buf: times dirent_sz db 0
	.parent_to_close: dw 0
	.disk_number: db 0
	.access_mode: db 0

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

	mov	es,dx
	mov	al,[es:file_ctrl_mode]
	cmp	al,open_access_read
	mov	ax,error_bad_type
	jne	.return

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
	ja	.no_next_sector
	jmp	.compute_bytes_to_read_from_sector
	.next_sector_error_io:
	mov	ax,error_disk_io
	jmp	.return
	.no_next_sector:
	xor	ax,ax
	cmp	byte [.dir_mode],1
	je	.return
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
	.dir_mode: db 0

do_file_close:
	push	ax
	push	bx
	cmp	dx,0xF000
	jae	.no_free ; don't free pseudohandles
	mov	ax,dx
	mov	bx,sys_heap_free
	int	0x20
	.no_free:
	pop	bx
	pop	ax
	iret

do_dir_read:
	push	es
	mov	es,dx
	mov	al,[es:file_ctrl_mode]
	cmp	al,open_access_directory
	jne	exception_handler
	mov	byte [es:file_ctrl_mode],open_access_read
	mov	word [es:file_ctrl_size_low],0xFFFF
	xor	ax,ax
	mov	es,ax
	mov	byte [es:do_file_read.dir_mode],1
	pop	es
	shl	cx,1
	shl	cx,1
	shl	cx,1
	shl	cx,1
	shl	cx,1
	mov	bx,sys_file_read
	int	0x20
	push	es
	xor	ax,ax
	mov	es,ax
	mov	byte [es:do_file_read.dir_mode],1
	mov	es,dx
	mov	byte [es:file_ctrl_mode],open_access_directory
	mov	cx,0xFFFF
	sub	cx,word [es:file_ctrl_size_low]
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	mov	word [es:file_ctrl_size_low],0
	pop	es
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
	jz	do_file_open_at
	dec	bl
	jz	do_file_close
	dec	bl
	jz	do_file_read
	dec	bl
	jz	do_file_open
	dec	bl
	jz	do_dir_read
	jmp	exception_handler

system_drive_number: db 0
disk_buffer_count:   db 0
disk_buffer_segment: dw 0
