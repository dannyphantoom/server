# Build directory
BUILD_DIR = build

# Default target
all: constants build

# Generate constants.txt from preprocessed constants.c
constants: $(BUILD_DIR)/constants.txt

$(BUILD_DIR)/constants.txt: backend/constants.c | $(BUILD_DIR)
	$(info --- Generating $(BUILD_DIR)/constants.txt ---)
	@gcc -E -P backend/constants.c > $(BUILD_DIR)/constants.txt

# Assemble and link the server
build: $(BUILD_DIR)/server

$(BUILD_DIR)/server: $(BUILD_DIR)/server.o | $(BUILD_DIR)
	$(info --- Linking $(BUILD_DIR)/server ---)
	@ld $(BUILD_DIR)/server.o -o $(BUILD_DIR)/server

$(BUILD_DIR)/server.o: backend/server.asm | $(BUILD_DIR)
	$(info --- Assembling backend/server.asm to $(BUILD_DIR)/server.o ---)
	@nasm -f elf64 backend/server.asm -o $(BUILD_DIR)/server.o

# Target to create the build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Clean up build artifacts
clean:
	$(info --- Cleaning contents of $(BUILD_DIR) ---)
	@-find $(BUILD_DIR)/ -mindepth 1 -delete

# Run the services using the dedicated shell script
run: all
	$(info --- Executing run.sh script ---)
	@sudo $(CURDIR)/run.sh

.PHONY: all constants build clean run
