; Assuming a 128KB EGA card.

; TODO Solid black/white block drawing can be sped up 2x.
; TODO 1px tall horizontal line block drawing can be optimized.
; TODO Glyph rendering: accurate horizontal clipping.
; TODO Cursor save/restore: clipping to screen bounds.
; TODO Cursor save/restore: don't bother if outside the clip list.
; TODO sys_invert_rect hasn't been tested with ds = 0.
; TODO Icon clipping bugs:
;	- Can't clip to draw just the last row of an icon.
;	- Move a window partially over an icon, then move the window to the right slightly (but still partially over the icon).

%include "bin/sansfont.s"

cursor_rows equ 19
; Cursor columns is fixed at 16 (2 bytes).

max_clip_rects equ 32

cursor_arrow:
         ; 1st OR    1st XOR   2nd OR    2nd XOR   padding   padding
	db 10000000b,10000000b,00000000b,00000000b,00000000b,00000000b
	db 11000000b,11000000b,00000000b,00000000b,00000000b,00000000b
	db 11100000b,10100000b,00000000b,00000000b,00000000b,00000000b
	db 11110000b,10010000b,00000000b,00000000b,00000000b,00000000b
	db 11111000b,10001000b,00000000b,00000000b,00000000b,00000000b
	db 11111100b,10000100b,00000000b,00000000b,00000000b,00000000b
	db 11111110b,10000010b,00000000b,00000000b,00000000b,00000000b
	db 11111111b,10000001b,00000000b,00000000b,00000000b,00000000b
	db 11111111b,10000000b,10000000b,10000000b,00000000b,00000000b
	db 11111111b,10000000b,11000000b,01000000b,00000000b,00000000b
	db 11111111b,10000000b,11100000b,00100000b,00000000b,00000000b
	db 11111111b,10000001b,11100000b,11100000b,00000000b,00000000b
	db 11111111b,10001001b,00000000b,00000000b,00000000b,00000000b
	db 11111111b,10011001b,00000000b,00000000b,00000000b,00000000b
	db 11100111b,10100100b,10000000b,10000000b,00000000b,00000000b
	db 11000111b,11000100b,10000000b,10000000b,00000000b,00000000b
	db 10000011b,10000010b,11000000b,01000000b,00000000b,00000000b
	db 00000011b,00000010b,11000000b,01000000b,00000000b,00000000b
	db 00000001b,00000001b,10000000b,10000000b,00000000b,00000000b

gfx_setup:
	.set_mode:
	mov	ax,0x0010
	int	0x10
	mov	word [gfx_width],640
	mov	word [gfx_clip_secondary + rect_r],640
	mov	word [gfx_height],350
	mov	word [gfx_clip_secondary + rect_b],350

	.set_cursor:
	mov	ax,(cursor_rows*3*4 + 8*cursor_rows*3*2 + 15) / 16 ; cursor behind and cursor shift data (see gfx_draw_cursor for why they need to be in the same seg)
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jz	out_of_memory_error
	mov	[gfx_cursor_seg],ax
	mov	si,cursor_arrow
	call	gfx_set_cursor

	.set_palette:
	mov	ax,0x1002
	mov	dx,.palette
	xor	bx,bx
	mov	es,bx
	int	0x10

	.alloc_clip_seg:
	mov	ax,(max_clip_rects * rect_sz + 15) / 16
	mov	bx,sys_heap_alloc
	int	0x20
	or	ax,ax
	jz	out_of_memory_error
	mov	[gfx_clip_seg],ax

;	.draw_test:
;	mov	word [gfx_clip_count],1
;	mov	ax,[gfx_clip_seg]
;	mov	es,ax
;	mov	word [es:rect_l],0
;	mov	word [es:rect_r],640
;	mov	word [es:rect_t],0
;	mov	word [es:rect_b],350
;	mov	cl,2
;	mov	di,.test_rect
;	mov	bx,sys_draw_block
;	int	0x20
;	mov	di,.test_rect2
;	mov	bx,sys_draw_invert
;	int	0x20
;	jmp	$
;	.test_rect: dw 0,200,0,200
;	.test_rect2: dw 100,300,100,300

;	.draw_test:
;	mov	word [gfx_clip_count],1
;	mov	ax,[gfx_clip_seg]
;	mov	es,ax
;	mov	word [es:rect_l],60
;	mov	word [es:rect_r],84
;	mov	word [es:rect_t],46
;	mov	word [es:rect_b],200
;	mov	cl,2
;	mov	di,.test_rect
;	mov	bx,sys_draw_block
;	int	0x20
;	mov	ax,0x0F00
;	mov	cx,50
;	mov	dx,50
;	mov	si,.test_string
;	mov	bx,sys_draw_text
;	int	0x20
;	jmp	$
;	.test_string: db 'Hello, world!',0
;	.test_rect: dw 0,200,0,200

;	.draw_speed_test:
;	mov	word [gfx_clip_count],1
;	mov	ax,[gfx_clip_seg]
;	mov	es,ax
;	mov	word [es:rect_l],0
;	mov	word [es:rect_r],640
;	mov	word [es:rect_t],0
;	mov	word [es:rect_b],350
;	mov	dx,110
;	.loop:
;	mov	cl,15
;	mov	di,.test_rect
;	mov	bx,sys_draw_block
;	int	0x20
;	mov	cx,3
;	add	[.test_rect + rect_t],cx
;	add	[.test_rect + rect_b],cx
;	dec	dx
;	jnz	.loop
;	jmp	$
;	.test_rect: dw 5,635,5,6

	.return:
	ret

	.palette: db 0x00, 0x01, 0x02, 0x23, 0x04, 0x05, 0x06, 0x07, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F

gfx_clip_rect_prepare: ; input: es:bx = rectangle, trashes: ax
	push	ds
	xor	ax,ax
	mov	ds,ax

	mov	ax,[es:bx + rect_l]
	cmp	ax,[gfx_clip_secondary + rect_l]
	mov	[gfx_clip_rect + rect_l],ax
	jge	.cl
	mov	ax,[gfx_clip_secondary + rect_l]
	mov	[gfx_clip_rect + rect_l],ax
	.cl:

	mov	ax,[es:bx + rect_r]
	cmp	ax,[gfx_clip_secondary + rect_r]
	mov	[gfx_clip_rect + rect_r],ax
	jle	.cr
	mov	ax,[gfx_clip_secondary + rect_r]
	mov	[gfx_clip_rect + rect_r],ax
	.cr:

	mov	ax,[es:bx + rect_t]
	cmp	ax,[gfx_clip_secondary + rect_t]
	mov	[gfx_clip_rect + rect_t],ax
	jge	.ct
	mov	ax,[gfx_clip_secondary + rect_t]
	mov	[gfx_clip_rect + rect_t],ax
	.ct:

	mov	ax,[es:bx + rect_b]
	cmp	ax,[gfx_clip_secondary + rect_b]
	mov	[gfx_clip_rect + rect_b],ax
	jle	.cb
	mov	ax,[gfx_clip_secondary + rect_b]
	mov	[gfx_clip_rect + rect_b],ax
	.cb:

	pop	ds
	ret

gfx_clip_subtract: ; input ds = 0, gfx_clip_rect = rect to subtract; trashes: ax, bx, di, es
	mov	es,[gfx_clip_seg]

	.check_input_valid:
	mov	ax,[gfx_clip_rect + rect_l]
	cmp	ax,[gfx_clip_rect + rect_r]
	jge	.return
	mov	ax,[gfx_clip_rect + rect_t]
	cmp	ax,[gfx_clip_rect + rect_b]
	jge	.return

	mov	bx,[gfx_clip_count]
	shl	bx,1
	shl	bx,1
	shl	bx,1
	.loop:
	or	bx,bx
	jz	.return
	sub	bx,rect_sz
	; Subtracting B (ds:gfx_clip_rect) from A (es:bx).

	.case1: ; A and B do not intersect.
	mov	ax,[es:bx + rect_l]
	cmp	ax,[gfx_clip_rect + rect_r]
	jge	.loop
	mov	ax,[es:bx + rect_r]
	cmp	ax,[gfx_clip_rect + rect_l]
	jle	.loop
	mov	ax,[es:bx + rect_t]
	cmp	ax,[gfx_clip_rect + rect_b]
	jge	.loop
	mov	ax,[es:bx + rect_b]
	cmp	ax,[gfx_clip_rect + rect_t]
	jle	.loop

	.case2: ; A is fully contained within B.
	mov	ax,[es:bx + rect_l]
	cmp	ax,[gfx_clip_rect + rect_l]
	jl	.case3
	mov	ax,[es:bx + rect_r]
	cmp	ax,[gfx_clip_rect + rect_r]
	jg	.case3
	mov	ax,[es:bx + rect_t]
	cmp	ax,[gfx_clip_rect + rect_t]
	jl	.case3
	mov	ax,[es:bx + rect_b]
	cmp	ax,[gfx_clip_rect + rect_b]
	jg	.case3
	mov	di,[gfx_clip_count] ; Delete swap.
	dec	di
	mov	[gfx_clip_count],di
	shl	di,1
	shl	di,1
	shl	di,1
	mov	ax,[es:di + rect_l]
	mov	[es:bx + rect_l],ax
	mov	ax,[es:di + rect_r]
	mov	[es:bx + rect_r],ax
	mov	ax,[es:di + rect_t]
	mov	[es:bx + rect_t],ax
	mov	ax,[es:di + rect_b]
	mov	[es:bx + rect_b],ax
	jmp	.loop

	.case3:
	mov	ax,[gfx_clip_rect + rect_t]
	cmp	ax,[es:bx + rect_t]
	jg	.case4
	mov	ax,[gfx_clip_rect + rect_b]
	cmp	ax,[es:bx + rect_b]
	jge	.case4
	mov	ax,[gfx_clip_rect + rect_r]
	cmp	ax,[es:bx + rect_r]
	jge	.case3a
	call	.append
	mov	ax,[gfx_clip_rect + rect_r]
	mov	[es:di + rect_l],ax
	mov	ax,[es:bx + rect_r]
	mov	[es:di + rect_r],ax
	mov	ax,[es:bx + rect_t]
	mov	[es:di + rect_t],ax
	mov	ax,[es:bx + rect_b]
	mov	[es:di + rect_b],ax
	.case3a:
	mov	ax,[gfx_clip_rect + rect_l]
	cmp	ax,[es:bx + rect_l]
	jle	.case3b
	call	.append
	mov	ax,[es:bx + rect_l]
	mov	[es:di + rect_l],ax
	mov	ax,[gfx_clip_rect + rect_l]
	mov	[es:di + rect_r],ax
	mov	ax,[es:bx + rect_t]
	mov	[es:di + rect_t],ax
	mov	ax,[gfx_clip_rect + rect_b]
	mov	[es:di + rect_b],ax
	.case3b:
	mov	ax,[gfx_clip_rect + rect_b]
	mov	[es:bx + rect_t],ax
	jmp	.loop

	.case4:
	mov	ax,[gfx_clip_rect + rect_b]
	cmp	ax,[es:bx + rect_b]
	jl	.case5
	mov	ax,[gfx_clip_rect + rect_t]
	cmp	ax,[es:bx + rect_t]
	jle	.case5
	mov	ax,[gfx_clip_rect + rect_r]
	cmp	ax,[es:bx + rect_r]
	jge	.case4a
	call	.append
	mov	ax,[gfx_clip_rect + rect_r]
	mov	[es:di + rect_l],ax
	mov	ax,[es:bx + rect_r]
	mov	[es:di + rect_r],ax
	mov	ax,[gfx_clip_rect + rect_t]
	mov	[es:di + rect_t],ax
	mov	ax,[es:bx + rect_b]
	mov	[es:di + rect_b],ax
	.case4a:
	mov	ax,[gfx_clip_rect + rect_l]
	cmp	ax,[es:bx + rect_l]
	jle	.case4b
	call	.append
	mov	ax,[es:bx + rect_l]
	mov	[es:di + rect_l],ax
	mov	ax,[gfx_clip_rect + rect_l]
	mov	[es:di + rect_r],ax
	mov	ax,[gfx_clip_rect + rect_t]
	mov	[es:di + rect_t],ax
	mov	ax,[es:bx + rect_b]
	mov	[es:di + rect_b],ax
	.case4b:
	mov	ax,[gfx_clip_rect + rect_t]
	mov	[es:bx + rect_b],ax
	jmp	.loop

	.case5:
	mov	ax,[gfx_clip_rect + rect_t]
	cmp	ax,[es:bx + rect_t]
	jg	.case6
	mov	ax,[gfx_clip_rect + rect_l]
	cmp	ax,[es:bx + rect_l]
	jle	.case6
	mov	ax,[gfx_clip_rect + rect_r]
	cmp	ax,[es:bx + rect_r]
	jge	.case5a
	call	.append
	mov	ax,[gfx_clip_rect + rect_r]
	mov	[es:di + rect_l],ax
	mov	ax,[es:bx + rect_r]
	mov	[es:di + rect_r],ax
	mov	ax,[es:bx + rect_t]
	mov	[es:di + rect_t],ax
	mov	ax,[es:bx + rect_b]
	mov	[es:di + rect_b],ax
	.case5a:
	mov	ax,[gfx_clip_rect + rect_l]
	mov	[es:bx + rect_r],ax
	jmp	.loop

	.case6:
	mov	ax,[gfx_clip_rect + rect_t]
	cmp	ax,[es:bx + rect_t]
	jg	.case7
	mov	ax,[gfx_clip_rect + rect_r]
	mov	[es:bx + rect_l],ax
	jmp	.loop

	.case7:
	mov	ax,[es:bx + rect_l]
	cmp	ax,[gfx_clip_rect + rect_l]
	jge	.case7a
	call	.append
	mov	ax,[es:bx + rect_l]
	mov	[es:di + rect_l],ax
	mov	ax,[gfx_clip_rect + rect_l]
	mov	[es:di + rect_r],ax
	mov	ax,[gfx_clip_rect + rect_t]
	mov	[es:di + rect_t],ax
	mov	ax,[gfx_clip_rect + rect_b]
	mov	[es:di + rect_b],ax
	.case7a:
	mov	ax,[es:bx + rect_r]
	cmp	ax,[gfx_clip_rect + rect_r]
	jle	.case7b
	call	.append
	mov	ax,[gfx_clip_rect + rect_r]
	mov	[es:di + rect_l],ax
	mov	ax,[es:bx + rect_r]
	mov	[es:di + rect_r],ax
	mov	ax,[gfx_clip_rect + rect_t]
	mov	[es:di + rect_t],ax
	mov	ax,[gfx_clip_rect + rect_b]
	mov	[es:di + rect_b],ax
	.case7b:
	call	.append
	mov	ax,[es:bx + rect_l]
	mov	[es:di + rect_l],ax
	mov	ax,[es:bx + rect_r]
	mov	[es:di + rect_r],ax
	mov	ax,[gfx_clip_rect + rect_b]
	mov	[es:di + rect_t],ax
	mov	ax,[es:bx + rect_b]
	mov	[es:di + rect_b],ax
	mov	ax,[gfx_clip_rect + rect_t]
	mov	[es:bx + rect_b],ax
	jmp	.loop

	.return:
	ret

	.append:
	mov	di,[gfx_clip_count]
	cmp	di,max_clip_rects - 1
	je	.overwrite ; TODO Better fallback?
	inc	word [gfx_clip_count]
	.overwrite:
	shl	di,1
	shl	di,1
	shl	di,1
	ret

gfx_set_cursor: ; input: ds = 0, si = cursor; trashes everything except ds
	mov	bp,si
	mov	ax,[gfx_cursor_seg]
	mov	es,ax

	mov	di,cursor_rows*3*4
	mov	bl,0
	.loop1:

	mov	cx,cursor_rows*6
	.inner1:
	lodsb

	mov	bh,bl
	or	bh,bh
	jz	.store1
	shr	al,1
	dec	bh
	jz	.store1
	shr	al,1
	dec	bh
	jz	.store1
	shr	al,1
	dec	bh
	jz	.store1
	shr	al,1
	dec	bh
	jz	.store1
	shr	al,1
	dec	bh
	jz	.store1
	shr	al,1
	dec	bh
	jz	.store1
	shr	al,1

	.store1:
	stosb
	loop	.inner1
	mov	si,bp

	inc	bl
	cmp	bl,8
	jne	.loop1

	mov	di,cursor_rows*3*4
	mov	bl,0
	.loop2:
	add	di,2

	mov	cx,cursor_rows*6-2
	.inner2:
	lodsb

	mov	bh,8
	sub	bh,bl
	shl	al,1
	dec	bh
	jz	.store2
	shl	al,1
	dec	bh
	jz	.store2
	shl	al,1
	dec	bh
	jz	.store2
	shl	al,1
	dec	bh
	jz	.store2
	shl	al,1
	dec	bh
	jz	.store2
	shl	al,1
	dec	bh
	jz	.store2
	shl	al,1
	dec	bh
	jz	.store2
	shl	al,1

	.store2:
	or	[es:di],al
	inc	di
	loop	.inner2
	mov	si,bp

	inc	bl
	cmp	bl,8
	jne	.loop2

	ret

gfx_draw_cursor: ; input: ds = 0; trashes: ax, bx, cx, dx, di
	push	ds
	push	es
	push	si
	mov	dx,0x3CE
	mov	al,0x05
	out	dx,al
	inc	dx
	xor	al,al
	out	dx,al ; read mode
	dec	dx
	mov	al,0x08
	out	dx,al
	inc	dx
	mov	al,0xFF
	out	dx,al ; masking

	mov	ax,[cursor_drawn_x]
	and	ax,7
	mov	cx,cursor_rows*3*2
	mul	cx
	mov	si,cursor_rows*3*4
	add	si,ax

	call	.prepare

	mov	cx,0x100
	call	.do_plane
	mov	cx,0x201
	call	.do_plane
	mov	cx,0x402
	call	.do_plane
	mov	cx,0x803
	call	.do_plane
	pop	si
	pop	es
	pop	ds
	ret

	.prepare:
	mov	ax,[cursor_drawn_y]
	mov	bx,640/8
	mul	bx
	mov	bx,[cursor_drawn_x]
	shr	bx,1
	shr	bx,1
	shr	bx,1
	add	bx,ax
	mov	ax,[gfx_cursor_seg]
	mov	es,ax
	mov	ax,0xA000
	mov	ds,ax
	xor	di,di
	ret

	.do_plane:
	mov	dx,0x3CE
	mov	al,0x04
	out	dx,al
	inc	dx
	mov	al,cl
	out	dx,al ; set read plane number
	mov	dx,0x3C4
	mov	al,0x02
	out	dx,al
	inc	dx
	mov	al,ch
	out	dx,al ; set write plane bit
	mov	cx,cursor_rows
	.loop:
	mov	al,[bx + 0]
	stosb
	mov	ax,[es:si + 0*2]
	or	[bx + 0],al
	xor	[bx + 0],ah
	mov	al,[bx + 1]
	stosb
	mov	ax,[es:si + 1*2]
	or	[bx + 1],al
	xor	[bx + 1],ah
	mov	al,[bx + 2]
	stosb
	mov	ax,[es:si + 2*2]
	or	[bx + 2],al
	xor	[bx + 2],ah
	add	bx,640/8
	add	si,6
	loop	.loop
	sub	bx,640/8*cursor_rows
	sub	si,cursor_rows*6
	ret

gfx_restore_beneath_cursor: ; input: ds = 0; trashes everything except ds, bp, si
	push	ds
	mov	dx,0x3CE
	mov	al,0x08
	out	dx,al
	inc	dx
	mov	al,0xFF
	out	dx,al ; masking
	call	gfx_draw_cursor.prepare
	mov	cl,1
	call	.copy_plane
	mov	cl,2
	call	.copy_plane
	mov	cl,4
	call	.copy_plane
	mov	cl,8
	call	.copy_plane
	pop	ds
	ret

	.copy_plane:
	mov	dx,0x3C4
	mov	al,0x02
	out	dx,al
	inc	dx
	mov	al,cl
	out	dx,al ; set write plane bit
	mov	cx,cursor_rows
	.loop:
	mov	al,[es:di + 0]
	mov	[bx + 0],al
	mov	al,[es:di + 1]
	mov	[bx + 1],al
	mov	al,[es:di + 2]
	mov	[bx + 2],al
	add	di,3
	add	bx,640/8
	loop	.loop
	sub	bx,640/8*cursor_rows
	ret

gfx_prepare_clipped_rect:
	.read_rect:
	push	word [di + rect_b]
	push	word [di + rect_t]
	push	word [di + rect_r]
	push	word [di + rect_l]
	xor	ax,ax
	mov	ds,ax

	.clamp_rectangle:
	mov	bx,[gfx_clip_rect + rect_l]
	pop	ax
	cmp	ax,bx
	jge	.cr2
	mov	ax,bx
	.cr2:
	mov	[.rect + rect_l],ax
	mov	bx,[gfx_clip_rect + rect_r]
	pop	ax
	cmp	ax,bx
	jle	.cr3
	mov	ax,bx
	.cr3:
	mov	[.rect + rect_r],ax
	mov	bx,[gfx_clip_rect + rect_t]
	pop	ax
	cmp	ax,bx
	jge	.cr4
	mov	ax,bx
	.cr4:
	mov	[.rect + rect_t],ax
	mov	bx,[gfx_clip_rect + rect_b]
	pop	ax
	cmp	ax,bx
	jle	.cr5
	mov	ax,bx
	.cr5:
	mov	[.rect + rect_b],ax

	.check_rect_valid:
	mov	ax,[.rect + rect_l]
	cmp	ax,[.rect + rect_r]
	jge	.invalid
	mov	ax,[.rect + rect_t]
	cmp	ax,[.rect + rect_b]
	jge	.invalid
	clc
	ret

	.invalid:
	stc
	ret

	.rect: dw 0,0,0,0

gfx_compute_block_info:
	mov	ax,0x00FF
	mov	cx,[gfx_prepare_clipped_rect.rect + rect_l]
	and	cx,7
	or	cx,cx
	jnz	.compute_left
	add	cx,8
	.compute_left:
	shr	al,1
	loop	.compute_left
	or	al,al
	jnz	.left_ready
	dec	al
	.left_ready:
	mov	cx,[gfx_prepare_clipped_rect.rect + rect_r]
	and	cx,7
	or	cx,cx
	jz	.right_ready
	.compute_right:
	shr	ah,1
	or	ah,0x80
	loop	.compute_right
	.right_ready:
	mov	bp,ax

	.compute_start_offset:
	mov	ax,[gfx_prepare_clipped_rect.rect + rect_t]
	mov	cx,[gfx_prepare_clipped_rect.rect + rect_b]
	sub	cx,ax
	mov	bx,640/8
	mul	bx
	mov	bx,ax

	.compute_width:
	mov	ax,[gfx_prepare_clipped_rect.rect + rect_l]
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	dx,[gfx_prepare_clipped_rect.rect + rect_r]
	shr	dx,1
	shr	dx,1
	shr	dx,1
	sub	dx,ax
	dec	dx
	add	bx,ax

	ret

gfx_draw_block_single:
	push	ds
	push	di
	push	cx

	call	gfx_prepare_clipped_rect
	jc	.return

	.set_color:
	and	cl,0xF
	mov	[.color],cl

	.set_main_color:
	mov	cl,[.color]
	mov	dx,0x3C4
	mov	al,0x02
	out	dx,al
	inc	dx
	mov	al,cl
	out	dx,al

	.disable_masking:
	mov	dx,0x3CE
	mov	al,0x08
	out	dx,al
	inc	dx
	mov	al,0xFF
	out	dx,al
	
	.set_graphics_segment:
	mov	ax,0xA000
	mov	es,ax

	call	gfx_compute_block_info

	cmp	dx,0xFFFF
	je	.thin

	push	dx
	mov	dx,0x3CF
	mov	ax,bp
	out	dx,al
	pop	dx
	mov	al,0xFF
	push	bx
	push	cx
	.left1:
	or	[es:bx],al
	add	bx,640/8
	loop	.left1
	pop	cx
	pop	bx

	or	dx,dx
	jz	.skip_middle1
	push	bx
	push	cx
	mov	al,0xFF
	push	dx
	mov	dx,0x3CF
	out	dx,al
	pop	dx
	inc	bx
	.middle1:
	mov	si,cx
	mov	cx,dx
	mov	di,bx
	rep	stosb
	mov	cx,si
	add	bx,640/8
	loop	.middle1
	pop	cx
	pop	bx
	.skip_middle1:

	push	dx
	mov	dx,0x3CF
	mov	ax,bp
	mov	al,ah
	out	dx,al
	pop	dx
	mov	al,0xFF
	push	bx
	push	cx
	add	bx,dx
	inc	bx
	.right1:
	or	[es:bx],al
	add	bx,640/8
	loop	.right1
	pop	cx
	pop	bx

	.set_opposite_color:
	push	cx
	push	dx
	mov	cl,[.color]
	xor	cl,0x0F
	mov	dx,0x3C4
	mov	al,0x02
	out	dx,al
	mov	dx,0x3C5
	mov	al,cl
	out	dx,al
	pop	dx
	pop	cx

	.prepare2:
	cmp	dx,0xFFFF
	je	.skip_middle2

	push	dx
	mov	dx,0x3CF
	mov	ax,bp
	out	dx,al
	pop	dx
	xor	al,al
	push	bx
	push	cx
	.left2:
	and	[es:bx],al
	add	bx,640/8
	loop	.left2
	pop	cx
	pop	bx
	      
	or	dx,dx
	jz	.skip_middle2
	push	dx
	mov	dx,0x3CF
	mov	al,0xFF
	out	dx,al
	inc	al
	pop	dx
	push	bx
	push	cx
	inc	bx
	.middle2:
	mov	si,cx
	mov	cx,dx
	mov	di,bx
	rep	stosb
	mov	cx,si
	add	bx,640/8
	loop	.middle2
	pop	cx
	pop	bx
	.skip_middle2:
	
	push	dx
	mov	dx,0x3CF
	mov	ax,bp
	mov	al,ah
	out	dx,al
	pop	dx
	xor	al,al
	push	bx
	push	cx
	add	bx,dx
	inc	bx
	.right2:
	and	[es:bx],al
	add	bx,640/8
	loop	.right2
	pop	cx
	pop	bx

	.reset_mask:
	mov	dx,0x3CE
	mov	al,0x08
	out	dx,al
	inc	dx
	mov	al,0xFF
	out	dx,al

	.return:
	pop	cx
	pop	di
	pop	ds
	ret

	.thin:
	mov	ax,bp
	and	ah,al
	mov	bp,ax
	jmp	.skip_middle1

	.color: db 0

gfx_draw_invert_plane:
	push	ds
	push	di

	call	gfx_prepare_clipped_rect
	jc	.return
	call	gfx_compute_block_info

	mov	ax,0xA000
	mov	es,ax

	mov	ax,bp
	cmp	dx,0xFFFF
	je	.thin

	push	bx
	push	cx
	.left1:
	xor	[es:bx],al
	add	bx,640/8
	loop	.left1
	pop	cx
	pop	bx

	or	dx,dx
	jz	.skip_middle1
	push	bx
	push	cx
	inc	bx
	.middle1:
	mov	si,cx
	mov	cx,dx
	mov	di,bx
	.middle_inner:
	xor	word [es:di],0xFF
	inc	di
	loop	.middle_inner
	mov	cx,si
	add	bx,640/8
	loop	.middle1
	pop	cx
	pop	bx
	.skip_middle1:

	push	bx
	push	cx
	add	bx,dx
	inc	bx
	.right1:
	xor	[es:bx],ah
	add	bx,640/8
	loop	.right1
	pop	cx
	pop	bx

	.return:
	pop	di
	pop	ds
	ret

	.thin:
	and	ah,al
	jmp	.skip_middle1

gfx_draw_invert_single:
	push	ds
	push	di
	push	cx

	mov	bx,0x0803
	call	gfx_set_plane
	call	gfx_draw_invert_plane
	mov	bx,0x0402
	call	gfx_set_plane
	call	gfx_draw_invert_plane
	mov	bx,0x0201
	call	gfx_set_plane
	call	gfx_draw_invert_plane
	mov	bx,0x0100
	call	gfx_set_plane
	call	gfx_draw_invert_plane

	pop	cx
	pop	di
	pop	ds
	ret

%macro draw_for_clip_rect_loop 1
	push	ax
	push	dx
	push	si
	push	bp
	push	es

	xor	ax,ax
	mov	es,ax
	mov	ax,[es:gfx_clip_seg]
	mov	bx,[es:gfx_clip_count]
	mov	es,ax
	shl	bx,1
	shl	bx,1
	shl	bx,1

	.clip_loop:
	or	bx,bx
	jz	.return
	sub	bx,rect_sz
	call	gfx_clip_rect_prepare
	push	bx
	push	es
	call	%1
	pop	es
	pop	bx
	jmp	.clip_loop

	.return:
	pop	es
	pop	bp
	pop	si
	pop	dx
	pop	ax
	iret
%endmacro

do_draw_block: 
	draw_for_clip_rect_loop gfx_draw_block_single

do_draw_invert: 
	.set_graphics_mode:
	push	ax
	push	dx
	mov	dx,0x3CE
	mov	al,0x08
	out	dx,al
	inc	dx
	mov	al,0xFF
	out	dx,al ; masking
	dec	dx
	mov	al,0x05
	out	dx,al
	inc	dx
	xor	al,al
	out	dx,al ; read mode
	pop	dx
	pop	ax

	draw_for_clip_rect_loop gfx_draw_invert_single

do_draw_frame:
	push	ds
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	mov	ax,[di + rect_l]
	mov	bx,[di + rect_r]
	mov	si,[di + rect_t]
	mov	dx,[di + rect_b]
	push	cx
	xor	cx,cx
	mov	ds,cx
	pop	cx
	mov	di,bx
	mov	bx,ax
	inc	bx
	call	.draw_rect_from_reg
	mov	bx,di
	mov	di,dx
	mov	dx,si
	inc	dx
	call	.draw_rect_from_reg
	mov	dx,di
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	mov	di,ax
	mov	ax,bx
	dec	ax
	call	.draw_rect_from_reg
	mov	ax,di
	mov	di,si
	mov	si,dx
	dec	si
	call	.draw_rect_from_reg
	mov	si,di
	inc	ax
	dec	bx
	inc	si
	dec	dx
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	mov	di,bx
	mov	bx,ax
	inc	bx
	call	.draw_rect_from_reg
	mov	bx,di
	mov	di,dx
	mov	dx,si
	inc	dx
	call	.draw_rect_from_reg
	mov	dx,di
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	mov	di,ax
	mov	ax,bx
	dec	ax
	call	.draw_rect_from_reg
	mov	ax,di
	mov	si,dx
	dec	si
	call	.draw_rect_from_reg
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	pop	ds
	iret

	.draw_rect_from_reg: 
	mov	[.rect + rect_l],ax
	mov	[.rect + rect_r],bx
	mov	[.rect + rect_t],si
	mov	[.rect + rect_b],dx
	push	di
	push	bx
	mov	di,.rect
	mov	bx,sys_draw_block
	int	0x20
	pop	bx
	pop	di
	ret

	.rect: dw 0,0,0,0

gfx_draw_glyph: ; input: ds = 0, es = 0xA000, si = high bit for new value, bx = glyph header, cx = x pos, dx = y pos; preserves: bx, cx, dx, ds, es, bp
	push	bx
	push	cx
	push	dx

	mov	[.temp2],cx

	.get_glyph_bits:
	mov	al,[bx + 2]
	cbw
	sub	cx,ax
	mov	al,[bx + 3]
	cbw
	sub	dx,ax
	mov	ax,dx
	mov	di,dx
	mov	dx,640 / 8
	mul	dx
	mov	dx,di ; dx = y top in pixels
	mov	di,cx
	shr	di,1
	shr	di,1
	shr	di,1
	add	di,ax ; di = destination bits
	and	cl,7 ; cl = destination offset within byte
	mov	al,[bx + 5] ; al = width
	mov	ah,[bx + 6] ; ah = height
	mov	bx,[bx]
	add	bx,def_font ; bx = source bits

	.horizontal_clip:
	mov	[.temp1],dx
	mov	dx,[.temp2]
	cmp	dx,[gfx_clip_rect + rect_r]
	jge	.return
	add	dl,al
	adc	dh,0
	cmp	dx,[gfx_clip_rect + rect_l]
	jl	.return
	; TODO Horizontal clipping within a single glyph.
	
	.convert_width_to_bytes:
	add	al,7
	shr	al,1
	shr	al,1
	shr	al,1

	.vertical_clip:
	mov	dx,[.temp1]
	cmp	dx,[gfx_clip_rect + rect_b]
	jge	.return
	add	dl,ah
	adc	dh,0
	cmp	dx,[gfx_clip_rect + rect_t]
	jl	.return
	sub	dx,[gfx_clip_rect + rect_b]
	cmp	dx,0
	jle	.no_clip_b
	sub	ah,dl
	.no_clip_b:
	mov	dx,[gfx_clip_rect + rect_t]
	sub	dx,[.temp1]
	cmp	dx,0
	jle	.no_clip_t
	sub	ah,dl
	or	ah,ah
	je	.return
	mov	[.temp1],ax
	mul	dl ; al (width) * dl
	add	bx,ax
	mov	ax,640 / 8
	mul	dl
	add	di,ax
	mov	ax,[.temp1]
	.no_clip_t:

	.scanline_loop:
	push	ax
	push	di
	.pixel_block_loop:
	mov	ch,cl
	mov	dh,[bx]
	.no_not:
	mov	dl,dh
	or	ch,ch
	jz	.put_byte1
	shr	dl,1
	dec	ch
	jz	.put_byte1
	shr	dl,1
	dec	ch
	jz	.put_byte1
	shr	dl,1
	dec	ch
	jz	.put_byte1
	shr	dl,1
	dec	ch
	jz	.put_byte1
	shr	dl,1
	dec	ch
	jz	.put_byte1
	shr	dl,1
	dec	ch
	jz	.put_byte1
	shr	dl,1
	dec	ch
	jz	.put_byte1
	.put_byte1:
	test	si,0x8000
	jz	.and_byte1
	or	[es:di],dl
	jmp	.wrote_byte1
	.and_byte1:
	not	dl
	and	[es:di],dl
	.wrote_byte1:
	inc	di
	mov	dl,dh
	mov	ch,8
	sub	ch,cl
	or	ch,ch
	jz	.put_byte2
	shl	dl,1
	dec	ch
	jz	.put_byte2
	shl	dl,1
	dec	ch
	jz	.put_byte2
	shl	dl,1
	dec	ch
	jz	.put_byte2
	shl	dl,1
	dec	ch
	jz	.put_byte2
	shl	dl,1
	dec	ch
	jz	.put_byte2
	shl	dl,1
	dec	ch
	jz	.put_byte2
	shl	dl,1
	dec	ch
	jz	.put_byte2
	.put_byte2:
	test	si,0x8000
	jz	.and_byte2
	or	[es:di],dl
	jmp	.wrote_byte2
	.and_byte2:
	not	dl
	and	[es:di],dl
	.wrote_byte2:
	inc	bx
	dec	al
	jnz	.pixel_block_loop
	pop	di
	pop	ax

	add	di,640 / 8
	dec	ah
	jnz	.scanline_loop

	.return:
	pop	dx
	pop	cx
	pop	bx
	ret

	.temp1: dw 0 ; there aren't enough registers!!
	.temp2: dw 0

gfx_draw_text_plane: ; bl = plane number, bh = 1 << bl, bp = low bit is bold flag
	call	gfx_set_plane

	push	cx
	push	dx
	push	si
	jmp	.next_glyph

	.glyph_loop:
	push	ds
	xor	di,di
	mov	ds,di

	.draw_glyph:
	push	si
	mov	si,ax
	xor	ah,ah
	shl	ax,1
	shl	ax,1
	shl	ax,1
	mov	bx,4 + def_font
	add	bx,ax
	call	gfx_draw_glyph
	test	bp,1
	jz	.not_bold
	inc	cx
	call	gfx_draw_glyph
	.not_bold:
	mov	bl,[bx + 4] ; glyph x advance
	xor	bh,bh
	add	cx,bx
	mov	ax,si
	pop	si

	pop	ds
	.next_glyph:
	lodsb
	or	al,al
	jnz	.glyph_loop

	pop	si
	pop	dx
	pop	cx
	ret

gfx_draw_text_single:
	.set_es:
	mov	bx,0xA000
	mov	es,bx
	
	mov	ah,0x80
	test	bp,0x800
	jnz	.draw_plane3
	xor	ah,ah
	.draw_plane3:
	mov	bx,0x0803
	call	gfx_draw_text_plane
	mov	ah,0x80
	test	bp,0x400
	jnz	.draw_plane2
	xor	ah,ah
	.draw_plane2:
	mov	bx,0x0402
	call	gfx_draw_text_plane
	mov	ah,0x80
	test	bp,0x200
	jnz	.draw_plane1
	xor	ah,ah
	.draw_plane1:
	mov	bx,0x0201
	call	gfx_draw_text_plane
	mov	ah,0x80
	test	bp,0x100
	jnz	.draw_plane0
	xor	ah,ah
	.draw_plane0:
	mov	bx,0x0100
	jmp	gfx_draw_text_plane

do_draw_text:
	push	ax
	push	es
	push	di
	push	bp

	mov	bp,ax

	.set_graphics_mode:
	push	dx
	mov	dx,0x3CE
	mov	al,0x08
	out	dx,al
	inc	dx
	mov	al,0xFF
	out	dx,al ; masking
	dec	dx
	mov	al,0x05
	out	dx,al
	inc	dx
	xor	al,al
	out	dx,al ; read mode
	pop	dx

	xor	ax,ax
	mov	es,ax
	mov	ax,[es:gfx_clip_seg]
	mov	bx,[es:gfx_clip_count]
	mov	es,ax
	shl	bx,1
	shl	bx,1
	shl	bx,1

	.clip_loop:
	or	bx,bx
	jz	.return
	sub	bx,rect_sz
	call	gfx_clip_rect_prepare
	push	bx
	push	es
	call	gfx_draw_text_single
	pop	es
	pop	bx
	jmp	.clip_loop

	.return:
	pop	bp
	pop	di
	pop	es
	pop	ax
	iret

gfx_draw_icon_plane:
	push	ax
	push	cx
	push	dx
	push	si
	push	di

	.get_out_in_position:
	push	ax
	push	dx
	xor	dh,dh
	mov	dl,al
	shr	dl,1
	mov	ax,[di + rect_t]
	mov	bp,ax
	mul	dx
	add	si,ax
	pop	dx
	mov	ax,dx
	mov	dx,640 / 8
	mul	dx
	mov	dx,ax
	mov	ax,[di + rect_l]
	shl	ax,1
	shl	ax,1
	xor	bh,bh
	add	bx,ax
	pop	ax

	xor	ah,ah
	shr	al,1

	.scanline_loop:
	cmp	bp,[di + rect_b]
	jge	.return
	push	bp
	push	ax
	push	bx
	push	cx

	.pixel_loop:
	mov	bp,bx
	shr	bp,1
	shr	bp,1
	cmp	bp,[di + rect_r]
	jge	.next_scanline

	.check_transparent:
	xor	bp,bp
	mov	es,bp
	mov	bp,bx
	shr	bp,1
	shr	bp,1
	shr	bp,1
	mov	al,[ds:si + bp]
	mov	ah,al
	test	bx,4
	jnz	.odd
	.even:
	and	ah,0xF0
	cmp	ah,0xB0
	je	.skip_bit
	jmp	.do_bit
	.odd:
	and	ah,0x0F
	cmp	ah,0x0B
	je	.skip_bit

	; al = pixel pair
	; bx = source x pos * 4 + plane
	; cx = dest x pos
	; si = source for plane with y pos
	; dx = dest for plane with y pos
	; preserve di
	.do_bit:
	push	bx
	and	bx,7
	mov	bl,[es:.lshift_lookup + bx]
	test	al,bl
	mov	ax,0xA000
	push	ax
	jz	.bit_off
	.bit_on:
	mov	bx,cx
	and	bx,7
	mov	ah,[es:.lshift_lookup + bx]
	mov	bx,cx
	shr	bx,1
	shr	bx,1
	shr	bx,1
	pop	es
	add	bx,dx
	or	[es:bx],ah
	jmp	.bit_done
	.bit_off:
	mov	bx,cx
	and	bx,7
	mov	ah,[es:.lshift_lookup_not + bx]
	mov	bx,cx
	shr	bx,1
	shr	bx,1
	shr	bx,1
	pop	es
	add	bx,dx
	and	[es:bx],ah
	.bit_done:
	pop	bx
	.skip_bit:

	.next_pixel:
	add	bx,4
	inc	cx
	jmp	.pixel_loop

	.next_scanline:
	add	dx,640 / 8
	pop	cx
	pop	bx
	pop	ax
	pop	bp
	inc	bp
	add	si,ax
	jmp	.scanline_loop

	.return:

	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	ax
	ret

	.lshift_lookup:     db 0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01
	.lshift_lookup_not: db 0x7F,0xBF,0xDF,0xEF,0xF7,0xFB,0xFD,0xFE

gfx_set_plane:
	push	ax
	push	dx
	mov	dx,0x3C4
	mov	al,0x02
	out	dx,al
	inc	dx
	mov	al,bh
	out	dx,al ; set write plane bit
	mov	dx,0x3CE
	mov	al,0x04
	out	dx,al
	inc	dx
	mov	al,bl
	out	dx,al ; set read plane number
	pop	dx
	pop	ax
	ret

gfx_draw_icon_single:
	push	bx
	push	cx
	push	dx

	.apply_clip:
	xor	bx,bx
	mov	es,bx
	mov	bx,[es:gfx_clip_rect + rect_r]
	sub	bx,cx
	add	bx,[ds:di + rect_l]
	cmp	bx,[di + rect_r]
	jg	.cr
	mov	[di + rect_r],bx
	.cr:
	mov	bx,[es:gfx_clip_rect + rect_b]
	sub	bx,dx
	add	bx,[ds:di + rect_t]
	cmp	bx,[di + rect_b]
	jg	.cb
	mov	[di + rect_b],bx
	.cb:
	mov	bx,[es:gfx_clip_rect + rect_l]
	sub	bx,cx
	cmp	bx,[di + rect_l]
	jl	.cl
	add	cx,bx
	sub	cx,[di + rect_l]
	mov	[di + rect_l],bx
	.cl:
	mov	bx,[es:gfx_clip_rect + rect_t]
	sub	bx,dx
	cmp	bx,[di + rect_t]
	jl	.ct
	add	dx,bx
	sub	dx,[di + rect_t]
	mov	[di + rect_t],bx
	.ct:
	mov	bx,[di + rect_l]
	cmp	bx,[di + rect_r]
	jge	.return
	mov	bx,[di + rect_t]
	cmp	bx,[di + rect_b]
	jge	.return

	.draw:
	mov	bx,0x0803
	call	gfx_set_plane
	call	gfx_draw_icon_plane
	mov	bx,0x0402
	call	gfx_set_plane
	call	gfx_draw_icon_plane
	mov	bx,0x0201
	call	gfx_set_plane
	call	gfx_draw_icon_plane
	mov	bx,0x0100
	call	gfx_set_plane
	call	gfx_draw_icon_plane

	.return:
	pop	dx
	pop	cx
	pop	bx
	ret

do_draw_icon:
	push	es
	push	bp

	.set_graphics_mode:
	push	ax
	push	dx
	mov	dx,0x3CE
	mov	al,0x08
	out	dx,al
	inc	dx
	mov	al,0xFF
	out	dx,al ; masking
	dec	dx
	mov	al,0x05
	out	dx,al
	inc	dx
	xor	al,al
	out	dx,al ; read mode
	pop	dx
	pop	ax

	xor	bx,bx
	mov	es,bx
	mov	bx,[es:gfx_clip_seg]
	push	word [es:gfx_clip_count]
	mov	es,bx
	pop	bx
	shl	bx,1
	shl	bx,1
	shl	bx,1

	.clip_loop:
	or	bx,bx
	jz	.return
	sub	bx,rect_sz
	push	ax
	call	gfx_clip_rect_prepare
	pop	ax
	push	es
	push	word [di + rect_l]
	push	word [di + rect_r]
	push	word [di + rect_t]
	push	word [di + rect_b]
	call	gfx_draw_icon_single
	pop	word [di + rect_b]
	pop	word [di + rect_t]
	pop	word [di + rect_r]
	pop	word [di + rect_l]
	pop	es
	jmp	.clip_loop

	.return:
	pop	bp
	pop	es
	iret

do_hit_test_text:
	; TODO
	xor	di,di
	iret

do_measure_text:
	push	ax
	push	bx
	push	cx
	push	dx
	push	si

	mov	dx,ax
	xor	cx,cx
	jmp	.next_glyph

	.glyph_loop:
	push	ds
	xor	bx,bx
	mov	ds,bx

	.advance_glyph:
	xor	ah,ah
	shl	ax,1
	shl	ax,1
	shl	ax,1
	mov	bx,4 + def_font
	add	bx,ax
	mov	bl,[bx + 4] ; glyph x advance
	xor	bh,bh
	add	cx,bx
	test	dl,1
	jz	.not_bold
	inc	cx
	.not_bold:

	pop	ds
	.next_glyph:
	lodsb
	or	al,al
	jnz	.glyph_loop

	push	ds
	xor	bx,bx
	mov	ds,bx
	mov	bx,[def_font + 0]
	mov	dx,[def_font + 2]
	pop	ds

	mov	word [es:di + rect_l],0
	mov	word [es:di + rect_r],cx
	neg	bx
	mov	word [es:di + rect_t],bx
	mov	word [es:di + rect_b],dx

	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret

do_display_word:
	push	bx
	push	cx
	push	dx
	push	si
	push	ds
	xor	cx,cx
	mov	ds,cx
	call	.get_char
	mov	[.buffer + 3],cl
	call	.shr4
	mov	[.buffer + 2],cl
	call	.shr4
	mov	[.buffer + 1],cl
	call	.shr4
	mov	[.buffer + 0],cl
	mov	si,.buffer
	call	print_cstring
	pop	ds
	pop	si
	pop	dx
	pop	cx
	pop	bx
	iret
	.shr4:
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	.get_char:
	mov	bx,ax
	and	bx,0x000F
	add	bx,.hex_chars
	mov	cl,[bx]
	ret
	.buffer: db 0,0,0,0,' ',0
	.hex_chars: db '0123456789ABCDEF'

do_gfx_syscall:
	or	bl,bl
	jz	do_draw_block
	dec	bl
	jz	do_draw_frame
	dec	bl
	jz	do_draw_text
	dec	bl
	jz	do_measure_text
	dec	bl
	jz	do_draw_icon
	dec	bl
	jz	do_draw_invert
	dec	bl
	jz	do_hit_test_text
	jmp	exception_handler

gfx_width:  dw 0
gfx_height: dw 0

gfx_clip_rect: dw 0,0,0,0
gfx_clip_secondary: dw 0,0,0,0
gfx_clip_seg: dw 0
gfx_clip_count: dw 0

gfx_cursor_seg: dw 0
