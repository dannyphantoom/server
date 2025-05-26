global _start              ; NASM uses 'global' not 'public'

section .text
_start:
    mov rdi, 2              ; AF_INET
    mov rsi, 1              ; SOCK_STREAM
    xor rdx, rdx            ; protocol = 0
    mov rax, 41             ; syscall: socket
    syscall
    mov r12, rax            ; save socket fd

    ; bind
    mov rdi, r12
    mov rsi, address
    mov rdx, 16
    mov rax, 49
    syscall

    ; listen
    mov rdi, r12
    mov rsi, 10
    mov rax, 50
    syscall

accept_loop:
    ; accept
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    mov rax, 43
    syscall
    mov r13, rax

    ; read request
    mov rdi, r13
    mov rsi, buffer
    mov rdx, 1024
    mov rax, 0
    syscall
    mov r15, rax

    ; check if POST
    mov eax, dword [buffer]
    cmp eax, 0x54534F50     ; 'POST'
    je handle_post

    ; ---- handle GET request ----
    ; build full path into path_buf starting with frontend_dir
    mov rdi, path_buf
    mov rsi, frontend_dir
    mov rcx, frontend_dir_len
    cld
    rep movsb
    mov rbx, rdi               ; save pointer after prefix

    ; rsi will point to requested path after "GET /"
    lea rsi, [buffer+4]
    cmp byte [rsi], '/'
    jne use_index
    inc rsi

copy_path:
    mov al, [rsi]
    cmp al, ' '
    je end_path_check
    cmp al, 13
    je end_path
    cmp al, '?'
    je end_path
    mov [rdi], al
    inc rdi
    inc rsi
    jmp copy_path

end_path_check:
    cmp rdi, rbx
    jne end_path
use_index:
    mov rsi, index_file
    mov rcx, index_file_len
    rep movsb

end_path:
    mov byte [rdi], 0

    ; determine content type based on file extension
    mov rsi, rdi               ; rdi currently at null terminator
    dec rsi
find_dot:
    cmp rsi, path_buf
    jb no_ext
    cmp byte [rsi], '.'
    je got_ext
    dec rsi
    jmp find_dot

no_ext:
    mov rsi, http_header_html
    mov rdx, http_header_html_len
    jmp open_send

got_ext:
    inc rsi
    mov al, [rsi]
    cmp al, 'c'
    jne check_js
    cmp byte [rsi+1], 's'
    jne check_js
    cmp byte [rsi+2], 's'
    jne check_js
    cmp byte [rsi+3], 0
    jne check_js
    mov rsi, http_header_css
    mov rdx, http_header_css_len
    jmp open_send

check_js:
    mov al, [rsi]
    cmp al, 'j'
    jne use_html
    cmp byte [rsi+1], 's'
    jne use_html
    cmp byte [rsi+2], 0
    jne use_html
    mov rsi, http_header_js
    mov rdx, http_header_js_len
    jmp open_send

use_html:
    mov rsi, http_header_html
    mov rdx, http_header_html_len

open_send:
    mov r8, rsi               ; preserve header pointer
    mov r9, rdx               ; preserve header length

    mov rdi, path_buf
    xor rsi, rsi
    xor rdx, rdx
    mov rax, 2
    syscall
    cmp rax, 0
    jl file_open_failed
    mov r14, rax

    mov rdi, r13
    mov rsi, r8
    mov rdx, r9
    mov rax, 1
    syscall                 ; write header

    ; send file content
    jmp read_loop

file_open_failed:
    mov rdi, r13
    mov rsi, fallback_msg
    mov rdx, fall_back_msg_len
    mov rax, 1             ; syscall: write
    syscall

    ; close client socket after sending error message
    mov rdi, r13
    mov rax, 3             ; close
    syscall
    jmp accept_loop

read_loop:
    ; read from file
    mov rdi, r14
    mov rsi, buffer2
    mov rdx, 256
    mov rax, 0
    syscall
    test rax, rax
    jz done_reading

    ; write to client
    mov rdx, rax
    mov rdi, r13
    mov rsi, buffer2
    mov rax, 1
    syscall
    jmp read_loop

done_reading:
    ; close sockets
    mov rdi, r13
    mov rax, 3
    syscall

    mov rdi, r14
    mov rax, 3
    syscall

    jmp accept_loop

handle_post:
    ; find start of body (look for CRLF CRLF)
    mov rsi, buffer
    mov rcx, r15
find_body:
    cmp rcx, 4
    jb no_body
    mov al, [rsi]
    cmp al, 13
    jne next_char
    mov al, [rsi+1]
    cmp al, 10
    jne next_char
    mov al, [rsi+2]
    cmp al, 13
    jne next_char
    mov al, [rsi+3]
    cmp al, 10
    jne next_char
    add rsi, 4
    sub rcx, 4
    jmp body_found
next_char:
    inc rsi
    dec rcx
    jmp find_body
no_body:
    ; If no CRLF CRLF found, treat entire buffer as body
    mov rsi, buffer
    mov rcx, r15
body_found:
    mov r8, rsi        ; message pointer
    mov r9, rcx        ; preserve message length

    ; open messages.txt for append
    mov rdi, msg_path
    mov rsi, 1089      ; O_WRONLY|O_CREAT|O_APPEND
    mov rdx, 420       ; 0644 octal
    mov rax, 2
    syscall
    mov r14, rax

    ; write message
    mov rdi, r14
    mov rsi, r8
    mov rdx, r9
    mov rax, 1
    syscall

    ; write newline
    mov rdi, r14
    mov rsi, newline
    mov rdx, 1
    mov rax, 1
    syscall

    ; close file
    mov rdi, r14
    mov rax, 3
    syscall

    ; send simple response
    mov rdi, r13
    mov rsi, post_resp
    mov rdx, post_resp_len
    mov rax, 1
    syscall

    mov rdi, r13
    mov rax, 3
    syscall

    jmp accept_loop

section .data
address:
    dw 2                    ; AF_INET
    ; Port 8080 in network byte order
    dw 0x901F               ; htons(8080)
    dd 0                    ; INADDR_ANY
    dq 0                    ; Padding

frontend_dir:
    db 'frontend/', 0
frontend_dir_len equ $ - frontend_dir

index_file:
    db 'index.html', 0
index_file_len equ $ - index_file

http_header_html:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/html', 13, 10
    db 13, 10
http_header_html_len equ $ - http_header_html

http_header_css:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/css', 13, 10
    db 13, 10
http_header_css_len equ $ - http_header_css

http_header_js:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: application/javascript', 13, 10
    db 13, 10
http_header_js_len equ $ - http_header_js

fallback_msg:
    db 'File not found', 13, 10
    db 'Content-Type: text/plain', 13, 10
    db 13, 10
    db 'Failed to open file', 10
fall_back_msg_len equ $ - fallback_msg

msg_path:
    db 'messages.txt', 0

post_resp:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/plain', 13, 10
    db 13, 10
    db 'Message received', 10
post_resp_len equ $ - post_resp
newline:
    db 10

section .bss
buffer resb 1024
buffer2 resb 256
path_buf resb 256
