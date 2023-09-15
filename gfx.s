; TODO Solid black/white block drawing can be sped up 2x.
; TODO Glyph rendering: clipping.

%include "bin/sansfont.s"

gfx_setup:
	mov	ax,0x0010
	int	0x10
	mov	word [gfx_width],640
	mov	word [gfx_height],350
	ret

do_draw_block:
	push	ax
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	push	es
	push	ds

	mov	ax,[di + rect_b]
	push	ax
	mov	ax,[di + rect_t]
	push	ax
	mov	ax,[di + rect_r]
	push	ax
	mov	ax,[di + rect_l]
	push	ax
	xor	ax,ax
	mov	ds,ax

	and	cl,0xF
	mov	[.color],cl

	.clamp_rectangle:
	mov	bx,640
	pop	ax
	or	ax,ax
	jge	.cr2
	xor	ax,ax
	.cr2:
	cmp	ax,bx
	jle	.cr3
	mov	ax,bx
	.cr3:
	mov	[.rect + rect_l],ax
	pop	ax
	or	ax,ax
	jge	.cr4
	xor	ax,ax
	.cr4:
	cmp	ax,bx
	jle	.cr5
	mov	ax,bx
	.cr5:
	mov	[.rect + rect_r],ax
	mov	bx,350
	pop	ax
	or	ax,ax
	jge	.cr6
	xor	ax,ax
	.cr6:
	cmp	ax,bx
	jle	.cr7
	mov	ax,bx
	.cr7:
	mov	[.rect + rect_t],ax
	pop	ax
	or	ax,ax
	jge	.cr8
	xor	ax,ax
	.cr8:
	cmp	ax,bx
	jle	.cr9
	mov	ax,bx
	.cr9:
	mov	[.rect + rect_b],ax

	.check_rect_valid:
	mov	ax,[.rect + rect_l]
	cmp	ax,[.rect + rect_r]
	jae	.return
	mov	ax,[.rect + rect_t]
	cmp	ax,[.rect + rect_b]
	jae	.return

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

	mov	ax,0x00FF
	mov	cx,[.rect + rect_l]
	and	cx,7
	.compute_left:
	shr	al,1
	loop	.compute_left
	or	al,al
	jnz	.left_ready
	dec	al
	.left_ready:
	mov	cx,[.rect + rect_r]
	and	cx,7
	.compute_right:
	shr	ah,1
	or	ah,0x80
	loop	.compute_right
	cmp	ah,0xFF
	jne	.right_ready
	inc	ah
	.right_ready:
	mov	bp,ax

	.compute_start_offset:
	mov	ax,[.rect + rect_t]
	mov	cx,[.rect + rect_b]
	sub	cx,ax
	mov	bx,640/8
	mul	bx
	mov	bx,ax

	.compute_width:
	mov	ax,[.rect + rect_l]
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	dx,[.rect + rect_r]
	shr	dx,1
	shr	dx,1
	shr	dx,1
	sub	dx,ax
	dec	dx
	add	bx,ax

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
	pop	ds
	pop	es
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	ax
	iret

	.thin:
	mov	ax,bp
	and	ah,al
	mov	bp,ax
	jmp	.skip_middle1

	.rect: dw 0,0,0,0
	.color: db 0

do_draw_frame:
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
	iret

	.draw_rect_from_reg: 
	mov	[do_draw_block.rect + rect_l],ax
	mov	[do_draw_block.rect + rect_r],bx
	mov	[do_draw_block.rect + rect_t],si
	mov	[do_draw_block.rect + rect_b],dx
	push	di
	push	bx
	mov	di,do_draw_block.rect
	mov	bx,sys_draw_block
	int	0x20
	pop	bx
	pop	di
	ret

gfx_draw_glyph: ; input: ds = 0, es = 0xA000, si = high bit for new value, bx = glyph header, cx = x pos, dx = y pos; preserves: bx, cx, dx, ds, es, bp
	push	bx
	push	cx
	push	dx

	.get_glyph_bits:
	mov	al,[bx + 2]
	cbw
	sub	cx,ax
	mov	al,[bx + 3]
	cbw
	sub	dx,ax
	mov	ax,dx
	mov	dx,640 / 8
	mul	dx
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

	.convert_width_to_bytes:
	add	al,7
	shr	al,1
	shr	al,1
	shr	al,1

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

	pop	dx
	pop	cx
	pop	bx
	ret

gfx_draw_text_plane: ; bl = plane number, bh = 1 << bl, bp = low bit is bold flag
	.set_plane:
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

do_draw_text:
	push	ax
	push	es
	push	di
	push	bp

	mov	bp,ax

	.set_es:
	mov	bx,0xA000
	mov	es,bx
	
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
	call	gfx_draw_text_plane

	pop	bp
	pop	di
	pop	es
	pop	ax
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
	jmp	exception_handler

gfx_width:  dw 0
gfx_height: dw 0
