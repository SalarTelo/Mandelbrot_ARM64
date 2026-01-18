# Mandelbrot Set Visualizer - ARM64

A high-performance Mandelbrot set visualizer written in pure ARM64 assembly for the core computation, with Objective-C for macOS window management and rendering.

## Features

- **Pure ARM64 Assembly**: Core Mandelbrot iteration algorithm implemented in ARM64 assembly for maximum performance
- **SIMD Floating Point**: Uses ARM64 NEON floating-point instructions for efficient computation
- **Native macOS**: Uses Cocoa framework for native window creation and rendering
- **Real-time Visualization**: Computes and displays the classic Mandelbrot set fractal

## Requirements

- macOS with Apple Silicon (ARM64/M1/M2/M3) or ARM64 compatible system
- Clang compiler with ARM64 support
- Cocoa framework (included with macOS)

## Building

Simply run `make` to build the application:

```bash
make
```

This will:
1. Compile the ARM64 assembly code (`src/mandelbrot.s`)
2. Compile the Objective-C window code (`src/main.m`)
3. Link everything together into an executable at `build/Mandelbrot`

## Running

After building, run the application:

```bash
make run
```

Or directly:

```bash
./build/Mandelbrot
```

A window will open displaying the Mandelbrot set fractal in vibrant colors.

## Project Structure

```
.
├── src/
│   ├── mandelbrot.s    # ARM64 assembly - Mandelbrot computation
│   └── main.m          # Objective-C - Window and rendering
├── Makefile            # Build system
└── README.md           # This file
```

## How It Works

### ARM64 Assembly (`mandelbrot.s`)

The core Mandelbrot computation is implemented in two functions:

1. **`mandelbrot_point`**: Computes the iteration count for a single complex number
   - Uses floating-point registers for complex number arithmetic
   - Implements the escape-time algorithm: z = z² + c
   - Returns iteration count before escape or maximum iterations

2. **`mandelbrot_compute`**: Processes the entire image buffer
   - Iterates over each pixel in the output buffer
   - Maps pixel coordinates to complex plane coordinates
   - Calls `mandelbrot_point` for each pixel
   - Converts iteration count to RGB color values

### Objective-C (`main.m`)

The window management uses standard Cocoa APIs:

- **`MandelbrotView`**: Custom NSView subclass
  - Allocates bitmap buffer on initialization
  - Calls ARM64 assembly function to compute Mandelbrot set
  - Renders the bitmap in `drawRect:`

- **`AppDelegate`**: Application delegate
  - Creates and configures the main window
  - Sets up the Mandelbrot view

## Configuration

You can modify the visualization parameters in `src/main.m`:

- `WINDOW_WIDTH`, `WINDOW_HEIGHT`: Output image dimensions (default: 800x600)
- `MAX_ITERATIONS`: Maximum iteration count (default: 256)
- `X_MIN`, `X_MAX`, `Y_MIN`, `Y_MAX`: Complex plane bounds (default: -2.5 to 1.0, -1.0 to 1.0)

## Cleaning

To clean build artifacts:

```bash
make clean
```

To rebuild from scratch:

```bash
make rebuild
```

## License

MIT License - See LICENSE file for details