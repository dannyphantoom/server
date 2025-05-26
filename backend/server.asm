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

    ; open("index.html", O_RDONLY)
    mov rdi, path
    xor rsi, rsi
    mov rax, 2
    syscall
    cmp rax, 0
    jl file_open_failed 
    mov r14, rax

    ; send HTTP header
    mov rdi, r13
    mov rsi, http_header
    mov rdx, http_header_len
    mov rax, 1
    syscall

    ;send file content
    jmp read_loop

file_open_failed:
    mov rdi, r13
    mov rsi, fallback_msg
    mov rdx, fall_back_msg_len
    mov rax, 1             ; syscall: write
    syscall

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

section .data
address:
    dw 2                    ; AF_INET
    dw 0x1F90 >> 8 | (0x1F90 << 8)               ; Port 8080 (big endian)
    dd 0                    ; INADDR_ANY
    dq 0                    ; Padding

path:
    db 'index.html', 0

http_header:
    db 'HTTP/1.1 200 OK', 13, 10
    db 'Content-Type: text/html', 13, 10
    db 13, 10
http_header_len equ $ - http_header
fallback_msg:
    db 'File not found', 13, 10
    db 'Content-Type: text/plain', 13, 10
    db 13, 10
    db 'Failed to open index.html', 10
fall_back_msg_len equ $ - fallback_msg

section .bss
buffer2 resb 256
