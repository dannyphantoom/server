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
    jne use_index_file_path ; If not "GET /...", it's "GET /actual_file.ext" or similar
    inc rsi                 ; Skip the first '/' if present ("GET /file" -> "file")

copy_path:
    mov al, [rsi]
    cmp al, ' '             ; Space ends the path
    je end_path_copy
    cmp al, 13              ; CR ends the path
    je end_path_copy
    cmp al, '?'             ; Query string starts, path ends
    je end_path_copy
    mov [rdi], al
    inc rdi
    inc rsi
    jmp copy_path

end_path_copy:
    cmp rdi, rbx            ; Check if anything was copied (path_buf still only frontend_dir)
    je use_index_file_path  ; If path was empty (e.g. "GET / "), serve index.html
    jmp determine_content_type_and_send

use_index_file_path:
    ; Path is empty or was just "/", so use index.html
    ; rdi should be pointing to path_buf + frontend_dir_len
    mov rsi, index_file
    mov rcx, index_file_len
    rep movsb
    ; Now path_buf contains frontend_dir + index_file

determine_content_type_and_send:
    mov byte [rdi], 0          ; Null-terminate the path in path_buf

    ; determine content type based on file extension in path_buf
    mov rsi, rdi               ; rdi is at the null terminator of path_buf
    dec rsi                    ; Point to last char of path
find_dot:
    cmp rsi, path_buf          ; Don't go before path_buf start
    jb no_ext_found
    cmp byte [rsi], '.'
    je got_ext_found
    dec rsi
    jmp find_dot

no_ext_found:                 ; Default to HTML if no extension
    mov r8, http_header_html   ; r8 = header pointer
    mov r9, http_header_html_len ; r9 = header length
    jmp attempt_open_send

got_ext_found:
    inc rsi                    ; Point after the dot
    mov al, [rsi]
    cmp al, 'c'
    jne check_js_ext
    cmp byte [rsi+1], 's'
    jne check_js_ext
    cmp byte [rsi+2], 's'
    jne check_js_ext
    cmp byte [rsi+3], 0        ; Ensure it's end of string or followed by parameters we ignore
    jne check_js_ext
    mov r8, http_header_css
    mov r9, http_header_css_len
    jmp attempt_open_send

check_js_ext:
    mov al, [rsi]
    cmp al, 'j'
    jne use_html_default
    cmp byte [rsi+1], 's'
    jne use_html_default
    cmp byte [rsi+2], 0
    jne use_html_default
    mov r8, http_header_js
    mov r9, http_header_js_len
    jmp attempt_open_send

use_html_default:              ; Fallback to HTML for unknown extensions
    mov r8, http_header_html
    mov r9, http_header_html_len

attempt_open_send:
    ; r8 (header pointer) and r9 (header length) are set.
    ; path_buf contains the full path to the file to serve.

    ; Open the file specified in path_buf
    mov rdi, path_buf
    xor rsi, rsi            ; flags = 0 (O_RDONLY)
    xor rdx, rdx            ; mode = 0
    mov rax, 2              ; syscall: open
    syscall
    cmp rax, 0
    jl handle_file_open_failed ; If open fails, jump to 404 handler
    mov r14, rax            ; Save file descriptor (r14)

    ; Send the 200 OK header (from r8, r9)
    mov rdi, r13            ; client socket fd
    mov rsi, r8             ; header string (200 OK type)
    mov rdx, r9             ; header length
    mov rax, 1              ; syscall: write
    syscall
    ; TODO: Check write syscall result for errors

    jmp send_file_content_loop ; Proceed to send file content

handle_file_open_failed:
    ; Send 404 Not Found header
    mov rdi, r13
    mov rsi, http_header_404
    mov rdx, http_header_404_len
    mov rax, 1
    syscall

    ; Send 404 Not Found body
    mov rdi, r13
    mov rsi, body_404
    mov rdx, body_404_len
    mov rax, 1
    syscall

    ; Close client socket
    mov rdi, r13
    mov rax, 3
    syscall
    jmp accept_loop

send_file_content_loop:
    ; read from file (fd in r14)
    mov rdi, r14
    mov rsi, buffer2
    mov rdx, 256
    mov rax, 0              ; syscall: read
    syscall
    test rax, rax           ; Check if bytes read is zero (EOF) or error
    jle done_sending_file   ; If rax <= 0 (EOF or error), finish

    ; write to client
    mov rdx, rax            ; number of bytes to write (from read)
    mov rdi, r13            ; client socket fd
    mov rsi, buffer2
    mov rax, 1              ; syscall: write
    syscall
    ; TODO: Check write syscall result for errors, especially short writes
    jmp send_file_content_loop

done_sending_file:
    ; Close client socket
    mov rdi, r13
    mov rax, 3              ; syscall: close
    syscall

    ; Close file
    mov rdi, r14
    mov rax, 3              ; syscall: close
    syscall

    jmp accept_loop

handle_post:
    ; find start of body (look for CRLF CRLF)
    mov rsi, buffer
    mov rcx, r15
find_body:
    cmp rcx, 4
    jb no_body_found
    mov al, [rsi]
    cmp al, 13
    jne next_char_in_body_search
    mov al, [rsi+1]
    cmp al, 10
    jne next_char_in_body_search
    mov al, [rsi+2]
    cmp al, 13
    jne next_char_in_body_search
    mov al, [rsi+3]
    cmp al, 10
    jne next_char_in_body_search
    add rsi, 4              ; Skip CRLFCRLF
    sub rcx, 4              ; Adjust length
    jmp post_body_found
next_char_in_body_search:
    inc rsi
    dec rcx
    jmp find_body
no_body_found:
    ; If no CRLF CRLF found, this is an error or simple POST, assume entire buffer is body
    ; For robustness, one might send an error here if headers are expected.
    mov rsi, buffer
    mov rcx, r15
post_body_found:
    mov r8, rsi        ; message pointer
    mov r9, rcx        ; preserve message length

    ; open messages.txt for append
    mov rdi, msg_path
    mov rsi, 1089      ; O_WRONLY|O_CREAT|O_APPEND (0x441)
    mov rdx, 0644o     ; 0644 octal file permissions
    mov rax, 2         ; syscall: open
    syscall
    ; TODO: Check open syscall result
    mov r14, rax       ; file descriptor for messages.txt

    ; write message
    mov rdi, r14
    mov rsi, r8
    mov rdx, r9
    mov rax, 1         ; syscall: write
    syscall

    ; write newline
    mov rdi, r14
    mov rsi, newline_char
    mov rdx, 1
    mov rax, 1         ; syscall: write
    syscall

    ; close file
    mov rdi, r14
    mov rax, 3         ; syscall: close
    syscall

    ; send simple 200 OK response for POST
    mov rdi, r13
    mov rsi, post_ok_response
    mov rdx, post_ok_response_len
    mov rax, 1         ; syscall: write
    syscall

    ; Close client socket
    mov rdi, r13
    mov rax, 3         ; syscall: close
    syscall

    jmp accept_loop

; --- Helper routines ---
; (No specific helper routines like map_path_to_file or set_content_type are needed with this refactor)
; strlen could be useful for debugging but not essential for current logic

section .data
address:
    dw 2                    ; AF_INET
    dw 0x901F               ; htons(8080)  (Port 8080 in network byte order)
    dd 0                    ; INADDR_ANY
    dq 0                    ; Padding

frontend_dir:
    db 'frontend/'          ; Note: No null terminator, length is explicit
frontend_dir_len equ $ - frontend_dir

index_file:
    db 'index.html', 0      ; Null-terminated
index_file_len equ $ - index_file - 1 ; Length excluding null

http_header_html:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/html; charset=utf-8', 13, 10
    db 'Connection: close', 13, 10 ; Important for simple servers
    db 13, 10
http_header_html_len equ $ - http_header_html

http_header_css:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/css; charset=utf-8', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
http_header_css_len equ $ - http_header_css

http_header_js:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: application/javascript; charset=utf-8', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
http_header_js_len equ $ - http_header_js

http_header_404:
    db 'HTTP/1.1 404 Not Found', 13, 10
    db 'Content-Type: text/html; charset=utf-8', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
http_header_404_len equ $ - http_header_404

body_404:
    db '<html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p>The requested resource could not be found on this server.</p></body></html>', 0
body_404_len equ $ - body_404 - 1

msg_path:
    db 'messages.txt', 0

post_ok_response:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/plain; charset=utf-8', 13, 10
    db 'Connection: close', 13, 10
    db 13, 10
    db 'Message received.', 10
post_ok_response_len equ $ - post_ok_response

newline_char:
    db 10

section .bss
buffer resb 1024             ; For incoming HTTP request
buffer2 resb 256             ; For reading file content
path_buf resb 256            ; For constructing file paths
