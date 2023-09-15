[bits 16]
[org 0x0000]
[cpu 8086]

%include "syscall.h"

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

	cli
	hlt

test_file_path: db '38.txt',0
test_file_path_2: db 'invalid.txt',0
test_file_output: times 16 db 0

	align 512
window_description:
	wnd_start 'Test Application'
	add_button 20, 100, 20, 45, 0, 0, 'Push'
	wnd_end
