# Makefile for Mandelbrot ARM64 Visualizer

# Application name
APP_NAME = Mandelbrot

# Directories
SRC_DIR = src
BUILD_DIR = build

# Source files
ASM_SRC = $(SRC_DIR)/mandelbrot.s
OBJC_SRC = $(SRC_DIR)/main.m

# Object files
ASM_OBJ = $(BUILD_DIR)/mandelbrot.o
OBJC_OBJ = $(BUILD_DIR)/main.o

# Compiler and flags
CC = clang
AS = clang
CFLAGS = -arch arm64 -framework Cocoa -framework Foundation
ASFLAGS = -arch arm64

# Optimization flags
OPTFLAGS = -O2

# Target executable
TARGET = $(BUILD_DIR)/$(APP_NAME)

# Default target
all: $(TARGET)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile assembly
$(ASM_OBJ): $(ASM_SRC) | $(BUILD_DIR)
	$(AS) $(ASFLAGS) -c $< -o $@

# Compile Objective-C
$(OBJC_OBJ): $(OBJC_SRC) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OPTFLAGS) -c $< -o $@

# Link executable
$(TARGET): $(ASM_OBJ) $(OBJC_OBJ)
	$(CC) $(CFLAGS) $(OPTFLAGS) $^ -o $@
	@echo "Build complete! Run with: ./$(TARGET)"

# Run the application
run: $(TARGET)
	./$(TARGET)

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

# Rebuild
rebuild: clean all

.PHONY: all run clean rebuild
