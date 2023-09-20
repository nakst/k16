; TODO have separate lists of free entries of different sizes

heap_entry_prev    equ 0x00
heap_entry_next    equ 0x02
heap_entry_status  equ 0x04
heap_entry_dllprev equ 0x06 ; the doubly linked list uses some of the heap entry header space
heap_entry_dllnext equ 0x08
heap_entry_dllhead equ 0x0A
heap_status_free   equ 0xF3EE
heap_status_used   equ 0xA110

out_of_memory_error:
	mov	si,.message
	call	print_cstring
	jmp	$
	.message: db 'Error: Not enough memory is available to run k16.',0

dll_alloc: ; output: ax = handle, carry set on error
	xor	ax,ax
	push	bx
	mov	bx,sys_heap_alloc
	int	0x20
	pop	bx
	or	ax,ax
	jz	.error
	push	es
	dec	ax
	mov	es,ax
	mov	[es:heap_entry_dllprev],ax
	mov	[es:heap_entry_dllnext],ax
	mov	byte [es:heap_entry_dllhead],1
	inc	ax
	pop	es
	clc
	ret
	.error:
	stc
	ret

dll_insert_start:
dll_insert_after: ; input: ax = existing item/list, bx = new item; preserves: ax, bx
	push	ax
	dec	ax
	push	es
	mov	es,ax
	mov	ax,[es:heap_entry_dllnext]
	pop	es
	inc	ax
	call	dll_insert_before
	pop	ax
	ret

dll_insert_end:
dll_insert_before: ; input: ax = existing item/list, bx = new item; preserves: ax, bx
	push	ax
	push	bx
	push	cx
	push	es
	dec	ax
	dec	bx
	mov	es,ax
	mov	cx,[es:heap_entry_dllprev]
	mov	[es:heap_entry_dllprev],bx
	mov	es,cx
	mov	[es:heap_entry_dllnext],bx
	mov	es,bx
	mov	[es:heap_entry_dllprev],cx
	mov	[es:heap_entry_dllnext],ax
	mov	byte [es:heap_entry_dllhead],0
	pop	es
	pop	cx
	pop	bx
	pop	ax
	ret

dll_remove: ; input: ax = item; preserves ax
	call	dll_is_list
	jc	exception_handler
	push	ax
	push	bx
	push	cx
	push	es
	dec	ax
	mov	es,ax
	mov	bx,[es:heap_entry_dllprev]
	mov	cx,[es:heap_entry_dllnext]
	mov	es,bx
	mov	[es:heap_entry_dllnext],cx
	mov	es,cx
	mov	[es:heap_entry_dllprev],bx
	pop	es
	pop	cx
	pop	bx
	pop	ax
	ret

dll_is_list: ; input: ax = item or list; output: carry set if list; preserves ax
	push	es
	push	ax
	dec	ax
	mov	es,ax
	mov	al,[es:heap_entry_dllhead]
	shr	al,1
	pop	ax
	pop	es
	ret

dll_first:
dll_next: ; input ax = item/list; output: ax = item/list
	push	es
	dec	ax
	mov	es,ax
	mov	ax,[es:heap_entry_dllnext]
	inc	ax
	pop	es
	ret

dll_last:
dll_prev: ; input ax = item/list; output: ax = item/list
	push	es
	dec	ax
	mov	es,ax
	mov	ax,[es:heap_entry_dllprev]
	inc	ax
	pop	es
	ret

heap_setup:
	int	0x12
	mov	bx,0x40
	mul	bx
	dec	ax
	mov	bx,[heap_start]
	mov	es,bx
	mov	word [es:heap_entry_prev],0x0000
	mov	word [es:heap_entry_status],heap_status_used ; prevent merging before start
	mov	word [es:0x10 + heap_entry_prev],bx
	inc	bx
	mov	word [es:heap_entry_next],bx
	mov	word [es:0x10 + heap_entry_next],ax
	mov	word [es:0x10 + heap_entry_status],heap_status_free
	mov	es,ax
	mov	word [es:heap_entry_prev],bx
	mov	word [es:heap_entry_next],0x0000
	mov	word [es:heap_entry_status],heap_status_used ; prevent merging after end
	ret

heap_walk:
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	xor	bx,bx
	mov	ds,bx
	mov	bx,[heap_start]
	mov	es,bx
	xor	cx,cx
	.loop:
	mov	si,.newline_string
	call	print_cstring
	mov	ax,es
	mov	bx,sys_display_word
	int	0x20
	mov	si,.colon_string
	call	print_cstring
	mov	ax,[es:heap_entry_prev]
	cmp	ax,cx
	jne	.corrupt
	mov	cx,es
	mov	bx,sys_display_word
	int	0x20
	mov	ax,[es:heap_entry_next]
	mov	bx,sys_display_word
	int	0x20
	mov	ax,[es:heap_entry_status]
	mov	bx,sys_display_word
	int	0x20
	mov	ax,[es:heap_entry_next]
	mov	es,ax
	or	ax,ax
	jnz	.loop
	mov	si,.newline_string
	call	print_cstring
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
	.corrupt:
	mov	si,.corrupt_string
	call	print_cstring
	jmp	$
	.corrupt_string: db 'Error: The heap has been corrupted.',0
	.newline_string: db 10,13,0
	.colon_string: db ': ',0

do_heap_alloc:
	push	ds
	push	es
	push	cx
	push	dx
	inc	ax ; make room for the header
	xor	bx,bx
	mov	ds,bx
	mov	bx,[heap_start]
	mov	es,bx
	xor	dx,dx ; stores return value
	.next_entry:
	mov	bx,[es:heap_entry_next]
	or	bx,bx
	jz	.return
	mov	es,bx
	.check_free:
	cmp	word [es:heap_entry_status],heap_status_free
	jne	.next_entry
	.check_space:
	mov	cx,[es:heap_entry_next]
	sub	cx,bx
	cmp	ax,cx
	ja	.next_entry
	mov	dx,bx
	je	.perfect_fit
	.unlink:
	mov	word [es:heap_entry_status],heap_status_used
	mov	cx,ax
	mov	ax,bx
	add	bx,cx
	mov	cx,[es:heap_entry_next]
	mov	[es:heap_entry_next],bx
	mov	es,bx
	mov	[es:heap_entry_prev],ax
	mov	[es:heap_entry_next],cx
	mov	word [es:heap_entry_status],heap_status_free
	mov	es,cx
	mov	[es:heap_entry_prev],bx
	jmp	.return
	.perfect_fit:
	mov	word [es:heap_entry_status],heap_status_used
	.return:
	mov	ax,dx
	pop	dx
	pop	cx
	pop	es
	pop	ds
	or	ax,ax
	jnz	.success
	iret
	.success: 
	inc	ax
	iret

do_heap_free:
	; NOTE DS is not set here!
	dec	ax
	push	es
	push	cx
	push	bx
	.set_status:
	mov	es,ax
	mov	ax,[es:heap_entry_status]
	cmp	ax,heap_status_used
	jne	heap_walk.corrupt
	mov	word [es:heap_entry_status],heap_status_free
	.merge_prev:
	mov	cx,[es:heap_entry_next]
	mov	bx,[es:heap_entry_prev]
	mov	es,bx
	mov	ax,[es:heap_entry_status]
	cmp	ax,heap_status_free
	jne	.merge_next
	mov	[es:heap_entry_next],cx
	mov	es,cx
	mov	[es:heap_entry_prev],bx
	.merge_next:
	mov	es,cx
	mov	ax,[es:heap_entry_status]
	cmp	ax,heap_status_free
	je	.merge_prev
	.return:
	pop	bx
	pop	cx
	pop	es
	iret

do_heap_syscall:
	or	bl,bl
	jz	do_heap_alloc
	dec	bl
	jz	do_heap_free
	jmp	exception_handler

heap_start: dw 0 ; as a multiple of 16 bytes
