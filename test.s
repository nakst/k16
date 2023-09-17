[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

id_ok          equ 1
id_push        equ 2
id_two_of_them equ 3

start:
	mov	ax,window_description
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	bx,cs
	add	ax,bx
	mov	bx,sys_wnd_create
	int	0x20

;	mov	bx,sys_file_open
;	mov	al,open_access_read
;	mov	si,test_file_path
;	int	0x20
;	mov	bx,sys_file_read
;	mov	cx,16
;	mov	di,test_file_output
;	int	0x20
;	mov	bx,sys_file_close
;	int	0x20
;	
;	mov	ax,[test_file_output + 14]
;	mov	bx,sys_display_word
;	int	0x20
;	
;	mov	bx,sys_file_open
;	mov	al,open_access_read
;	mov	si,test_file_path_2
;	int	0x20
;	mov	bx,sys_display_word
;	int	0x20

	iret

window_callback:
	cmp	cx,msg_clicked
	je	.clicked
	iret

	.clicked:
	cmp	dx,id_push
	je	.push
	cmp	dx,id_ok
	je	.ok
	iret

	.ok:
	; TODO Close the alert.
	mov	ax,[alert_handle]
	mov	bx,sys_wnd_destroy
	int	0x20
	iret

	.push:
	mov	ax,alert_description
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	mov	bx,cs
	add	ax,bx
	mov	bx,sys_wnd_create
	int	0x20
	mov	[alert_handle],ax
	iret

test_file_path: db '38.txt',0
test_file_path_2: db 'invalid.txt',0
test_file_output: times 16 db 0
alert_handle: dw 0

	align 512 ; this only needs to be 16-byte aligned, but we're testing reading large files
window_description:
	wnd_start 'Test Application', window_callback
	add_button 20, 100, 20, 45, id_push, 0, 'Push'
	add_button 20, 100, 20 + 30, 45 + 30, id_two_of_them, 0, 'Two of them'
	wnd_end

	align 16
alert_description:
	wnd_start 'Alert', window_callback
	add_static 20, 180, 20, 45, 0, 0, 'You clicked the button.'
	add_button 20, 100, 20 + 30, 45 + 30, id_ok, 0, 'OK'
	wnd_end
