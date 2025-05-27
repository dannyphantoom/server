# Default target
all: constants build

# Generate constants.txt from preprocessed constants.c
constants:
	$(info --- Generating constants.txt ---)
	@gcc -E -P backend/constants.c > constants.txt

# Assemble and link the server
build:
	$(info --- Assembling and linking server ---)
	@nasm -f elf64 backend/server.asm -o server.o
	@ld server.o -o server

# Clean up build artifacts
clean:
	$(info --- Cleaning build artifacts ---)
	@rm -f server server.o constants.txt

# Define the script for the run target
# This script is executed by /bin/sh -c
define RUN_SCRIPT
set -e; \
PID_PYTHON=\"\"; \
cleanup() { \
    echo; \
    echo \"INFO: Trap caught (signal: $$1), cleaning up Python app (PID $$PID_PYTHON).\"; \
    if [ -n \"$$PID_PYTHON\" ]; then \
        kill \"$$PID_PYTHON\" 2>/dev/null || echo \"Python app (PID $$PID_PYTHON) already stopped or not found.\"; \
        echo \"Python app cleanup attempted.\"; \
    fi; \
    if [ \"$$1\" = \"INT\" ] || [ \"$$1\" = \"TERM\" ]; then \
        exit 130; \
    fi; \
}; \
trap 'cleanup INT' INT; \
trap 'cleanup TERM' TERM; \
trap 'cleanup EXIT' EXIT; \
echo \"Starting user-space chat app in the background...\"; \
python userspace_chat_app/chat_app_receiver.py & \
PID_PYTHON=$$!; \
echo \"User-space chat app started with PID $$PID_PYTHON.\"; \
echo \"Waiting 2 seconds for the chat app to initialize FIFO...\"; \
sleep 2; \
echo \"Starting assembly server in the foreground (requires sudo)...\"; \
sudo ./server; \
SERVER_EXIT_CODE=$$?; \
echo \"Assembly server has finished with exit code $$SERVER_EXIT_CODE.\"; \
PID_PYTHON=\"\"; \
exit $$SERVER_EXIT_CODE
endef

# Run both the user-space app (background) and the server (foreground)
run: all
	$(info --- Preparing to run services ---)
	@/bin/sh -c "$(RUN_SCRIPT)"

# A target to stop the backgrounded python app if needed, though trap should handle it.
# This is a bit more involved to do reliably from a separate make target without PID files.
# stop_chat_app:
# 	@echo "Attempting to stop user-space chat app..."
# 	@pkill -f "python userspace_chat_app/chat_app_receiver.py" || echo "Chat app not found or already stopped."

.PHONY: all constants build clean run
