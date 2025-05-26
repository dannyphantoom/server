# Default target
all: constants build

# Generate constants.txt from preprocessed constants.c
constants:
	gcc -E -P constants.c > constants.txt

# Assemble and link the server
build:
	nasm -f elf64 server.asm -o server.o
	ld server.o -o server

# Clean up build artifacts
clean:
	rm -f server server.o constants.txt
run: all
	sudo ./server
