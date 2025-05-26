# Default target
all: constants build

# Generate constants.txt from preprocessed constants.c
constants:
	gcc -E -P backend/constants.c > constants.txt

# Assemble and link the server
build:
	nasm -f elf64 backend/server.asm -o server.o
	ld server.o -o server

# Clean up build artifacts
clean:
	rm -f server server.o constants.txt

# Run both the user-space app (background) and the server (foreground)
run: all
	@echo "Starting user-space chat app in the background..."
	python userspace_chat_app/chat_app_receiver.py & \
	PID_PYTHON=$$! ; \
	 trap "echo 'Stopping Python app (PID $$PID_PYTHON)...'; kill $$PID_PYTHON; exit" INT TERM EXIT; \
	@echo "Waiting a moment for the chat app to initialize the FIFO..."
	sleep 2 # Give the Python app a moment to create the FIFO
	@echo "Starting assembly server in the foreground..."
	sudo ./server

# A target to stop the backgrounded python app if needed, though trap should handle it.
# This is a bit more involved to do reliably from a separate make target without PID files.
# stop_chat_app:
# 	@echo "Attempting to stop user-space chat app..."
# 	@pkill -f "python userspace_chat_app/chat_app_receiver.py" || echo "Chat app not found or already stopped."

.PHONY: all constants build clean run
