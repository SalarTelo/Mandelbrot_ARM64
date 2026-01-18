# Mandelbrot set - ARM64

An _**attempt**_ at a high-performance Mandelbrot set renderer written entirely in **AArch64 Assembly** for macOS.

## Features

- **Pure Assembly**: Core rendering, math, and logic processing are hand-written in AArch64 assembly.
- **Multithreaded**: Utilizes CPU cores efficiently for parallel line rendering.
- **Double Precision**: 64-bit floating-point arithmetic for deep zooming capabilities.
- **Dynamic Coloring**: "Bahamas Water" theme with smooth palette cycling animation.

## Controls

- **Left Click**: Zoom In (slower, predictable speed)
- **Right Click**: Zoom Out
- **Mouse Movement**: Zoom centers on mouse cursor

## Build Instructions

Requirements: macOS (ARM64), CMake.

```bash
mkdir build
cd build
cmake ..
make
./app
```

## Structure

- `src/main.S`: Entry point, window management, event loop.
- `src/mandelbrot.S`: Main rendering loop and threading logic.
- `src/mandelbrot_helper.S`: Math helpers and coloring algorithms.
- `src/mandelbrot_palette.S`: Runtime generation of the 256-color cosine palette.
- `src/obj_window.m`: Objective-C windowing bridge.
