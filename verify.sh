#!/bin/bash
# Build verification script for Mandelbrot ARM64
# This script verifies that the project structure and code are correct

echo "==================================="
echo "Mandelbrot ARM64 - Build Verification"
echo "==================================="
echo ""

# Check architecture
ARCH=$(uname -m)
echo "Current architecture: $ARCH"

# Check for required files
echo ""
echo "Checking project structure..."
REQUIRED_FILES=(
    "src/mandelbrot.s"
    "src/main.m"
    "Makefile"
    "README.md"
)

ALL_FOUND=true
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ Found: $file"
    else
        echo "✗ Missing: $file"
        ALL_FOUND=false
    fi
done

if [ "$ALL_FOUND" = true ]; then
    echo ""
    echo "✓ All required files present"
else
    echo ""
    echo "✗ Some files are missing"
    exit 1
fi

# Check if we're on ARM64
echo ""
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    echo "✓ ARM64 architecture detected"
    
    # Check if on macOS
    if [ "$(uname -s)" = "Darwin" ]; then
        echo "✓ macOS detected"
        echo ""
        echo "Attempting to build..."
        make clean
        if make; then
            echo ""
            echo "✓ Build successful!"
            echo ""
            echo "You can now run the application with:"
            echo "  make run"
            echo "  or"
            echo "  ./build/Mandelbrot"
        else
            echo ""
            echo "✗ Build failed"
            exit 1
        fi
    else
        echo "⚠ Not running on macOS - Cocoa framework not available"
        echo "  This project requires macOS to build and run"
        exit 0
    fi
else
    echo "⚠ Not running on ARM64 architecture"
    echo "  This project is designed for ARM64 (Apple Silicon, etc.)"
    echo "  Current architecture: $ARCH"
    echo ""
    echo "You can still verify the assembly syntax with:"
    echo "  clang -target arm64-apple-macos11 -arch arm64 -c src/mandelbrot.s -o /tmp/test.o"
fi

echo ""
echo "==================================="
