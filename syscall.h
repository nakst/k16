; TODO Test sys_heap_alloc works with a different DS value than the system's.
; TODO Color management; color settings.

; to make a system call, put the number in bx, cld, and then int 0x20
; all inputs (including bx) and flags are scratch registers unless otherwise noted!
sys_display_word   equ 0x0000 ; input: ax = value to print
sys_app_start      equ 0x0001 ; input: si = cstr path; output: ax = error code, si = result from app (trashed if error)
sys_heap_alloc     equ 0x0100 ; input: ax = memory units to alloc (multiples of 16 bytes); output: ax = offset in memory units or 0 on error
sys_heap_free      equ 0x0101 ; input: ax = offset in memory units
sys_file_open      equ 0x0200 ; input: al = access mode, si = cstr path; output: ax = error code, dx = handle (trashed if error)
sys_file_close     equ 0x0201 ; input: dx = handle
sys_file_read      equ 0x0202 ; input: cx = byte count, dx = handle, di = output buffer; output: ax = error code; preserves: dx
; sys_file_write   equ 0x0203 ; input: cx = byte count, dx = handle, di = input buffer; output: ax = error code
sys_draw_block     equ 0x0300 ; input: cl = color, di = rect; preserves: cl, di
sys_draw_frame     equ 0x0301 ; input: cx = style, di = rect; preserves: cx, di
sys_draw_text      equ 0x0302 ; input: ah = color, al = bold flag, cx = x pos, dx = y pos, si = cstr; preserves: ax, cx, dx, si
sys_measure_text   equ 0x0303 ; input: al = bold flag, [ds:]si = cstr, [es:]di = out rect; preserves: al, si, di
sys_wnd_create     equ 0x0400 ; input: ax = window description; output: ax = handle (0 if error)
sys_wnd_destroy    equ 0x0401 ; input: ax = window handle
sys_wnd_redraw     equ 0x0402 ; input: ax = window handle, dx = item id
sys_wnd_get_extra  equ 0x0403 ; input: ax = window handle; output: es = extra segment; preserves: ax

error_none      equ 0x00
error_corrupt   equ 0x01
error_not_found equ 0x02
error_disk_io   equ 0x03
error_bad_name  equ 0x04
error_no_memory equ 0x05
error_eof       equ 0x06
error_exists    equ 0x07
error_too_large equ 0x08

open_access_read                  equ 0x00
; open_access_truncate            equ 0x01
; open_access_append              equ 0x02
; open_access_create              equ 0x03
; open_access_create_or_truncate  equ 0x04
; open_access_create_or_append    equ 0x05

file_ctrl_first_sector equ 0x00 ; TODO Is this field needed?
file_ctrl_curr_sector  equ 0x02
file_ctrl_off_in_sect  equ 0x04
file_ctrl_dirent_sect  equ 0x06
file_ctrl_size_low     equ 0x08 ; when reading, this is the remaining size
file_ctrl_size_high    equ 0x0A
file_ctrl_drive        equ 0x0C
file_ctrl_mode         equ 0x0D
file_ctrl_dirent_index equ 0x0E
file_ctrl_sz           equ 0x10

rect_l  equ 0x00 ; signed words
rect_r  equ 0x02
rect_t  equ 0x04
rect_b  equ 0x06
rect_sz equ 0x08

frame_3d_out equ 0x870F
frame_3d_in  equ 0x70F8
frame_pushed equ 0x8800
frame_window equ 0x8F07

wnd_item_code   equ 0x00
wnd_item_strlen equ 0x01
wnd_item_l      equ 0x02
wnd_item_r      equ 0x04
wnd_item_t      equ 0x06
wnd_item_b      equ 0x08
wnd_item_id     equ 0x0A
wnd_item_flags  equ 0x0C
wnd_item_string equ 0x0E ; size is 0x0E + length of string

wnd_item_flag_pushed equ (1 << 0)
wnd_item_flag_grow_l equ (1 << 1) ; l is an offset from the right side of the window
wnd_item_flag_grow_r equ (1 << 2) ; r is an offset from the right side of the window
wnd_item_flag_grow_t equ (1 << 3) ; t is an offset from the bottom side of the window
wnd_item_flag_grow_b equ (1 << 4) ; b is an offset from the bottom side of the window

wnd_item_code_button equ 0x01
wnd_item_code_title  equ 0x02
wnd_item_code_static equ 0x03
wnd_item_code_custom equ 0x04

wnd_desc_callback equ 0x00
wnd_desc_extra    equ 0x02 ; extra memory to allocate, access with sys_wnd_get_extra
wnd_desc_iwidth   equ 0x04
wnd_desc_iheight  equ 0x06
wnd_desc_sz       equ 0x08

msg_btn_clicked  equ 0x0001 ; ax = window, dx = id
msg_custom_draw  equ 0x0002 ; ax = window, dx = id, si = rect segment, di = rect
msg_custom_mouse equ 0x0003 ; ax = window, dx = id, si = [bit 0 = down, bit 1 = button]
msg_custom_drag  equ 0x0004 ; ax = window, dx = id
; TODO msg_resize, msg_move, msg_close

%macro add_wnditem 8 ; type, left, right, top, bottom, id, flags, string
	db	%1
	db	%strlen(%8)+1
	dw	%2
	dw	%3
	dw	%4
	dw	%5
	dw	%6
	dw	%7
	db	%8,0
%endmacro

%macro add_button 7 ; left, right, top, bottom, id, flags, string
	add_wnditem wnd_item_code_button, %1, %2, %3, %4, %5, %6, %7
%endmacro

%macro add_static 7 ; left, right, top, bottom, id, flags, string
	add_wnditem wnd_item_code_static, %1, %2, %3, %4, %5, %6, %7
%endmacro

%macro add_custom 7 ; left, right, top, bottom, id, flags, string
	add_wnditem wnd_item_code_custom, %1, %2, %3, %4, %5, %6, %7
%endmacro

%macro wnd_start 5 ; title, callback, extra bytes, init width, init height
	dw	%2
	dw	(%3 + 15) / 16
	dw	%4
	dw	%5
	add_wnditem wnd_item_code_title, 0, 0, -20, -2, 0, wnd_item_flag_grow_r, %1
%endmacro

%macro wnd_end 0
	db	0x00
%endmacro
