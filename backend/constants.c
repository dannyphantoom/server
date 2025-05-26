#include <sys/syscall.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>

socket = SYS_socket;
bind = SYS_bind;
listen = SYS_listen;
accept = SYS_accept;
read = SYS_read;
open = SYS_open;
write = SYS_write;
af_inet = AF_INET;
sock_stream = 1; /* SOCK_STREAM */
