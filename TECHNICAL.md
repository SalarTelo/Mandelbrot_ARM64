# Technical Details

## Mandelbrot Set Algorithm

The Mandelbrot set is defined as the set of complex numbers `c` for which the iterative function:

```
z(n+1) = z(n)² + c
```

does not diverge when starting from `z(0) = 0`.

In practice, we test for divergence by checking if `|z|² > 4` (escape radius).

## ARM64 Assembly Implementation

### Register Usage in `mandelbrot_point`

- **Input Parameters:**
  - `d0`: Real part of complex number (x coordinate)
  - `d1`: Imaginary part of complex number (y coordinate)
  - `w0`: Maximum iteration count

- **Working Registers:**
  - `d2`: c_real (constant, input x)
  - `d3`: c_imag (constant, input y)
  - `d4`: z_real (current iteration)
  - `d5`: z_imag (current iteration)
  - `d6`: Constant 4.0 (escape radius squared)
  - `d7`: z_real² (temporary)
  - `d8`: z_imag² (temporary)
  - `d9`: max_iter (saved from w0)
  - `d10`: z_real² + z_imag² (magnitude squared)
  - `d11`: Temporary for calculations

- **Return Value:**
  - `w0`: Iteration count before escape (or max_iter if in set)

### Complex Number Arithmetic

For complex numbers `z = a + bi` and `c = x + yi`:

**Squaring:** `z² = (a² - b²) + (2ab)i`

This is implemented as:
```assembly
fmul    d7, d4, d4      // a²
fmul    d8, d5, d5      // b²
fsub    d4, d7, d8      // new real = a² - b²
fmul    d11, d4, d5     // a * b
fadd    d11, d11, d11   // 2ab
fmov    d5, d11         // new imag = 2ab
```

**Addition:** `z² + c = (a² - b² + x) + (2ab + y)i`

### Color Mapping

The iteration count is mapped to RGB color using simple bit shifting:
- Red: `(iter * 4) & 0xFF`
- Green: `(iter * 8) & 0xFF`
- Blue: `(iter * 16) & 0xFF`

Points in the set (reached max_iter) are rendered black.

## Performance Considerations

### Floating-Point Operations

The ARM64 NEON instruction set provides efficient floating-point operations:
- `fmul`: Single-cycle throughput on most Apple Silicon
- `fadd`/`fsub`: Single-cycle throughput
- `fcmp`: Comparison with immediate branching

### Memory Layout

The image buffer uses RGBA format (4 bytes per pixel):
```
[R][G][B][A] [R][G][B][A] ...
```

Pixels are stored in row-major order: `offset = (y * width + x) * 4`

### Optimization Opportunities

Current implementation focuses on clarity. Potential optimizations:

1. **SIMD Vectorization**: Process 2-4 pixels simultaneously using NEON vector instructions
2. **Loop Unrolling**: Reduce branch overhead in iteration loop
3. **Early Exit**: More sophisticated escape detection
4. **Adaptive Iteration**: Variable max_iter based on region
5. **Multi-threading**: Divide image into tiles for parallel processing

## Cocoa Integration

The Objective-C layer handles:
1. **Window Creation**: Standard NSWindow with title bar and controls
2. **Bitmap Management**: NSBitmapImageRep for efficient rendering
3. **Buffer Allocation**: Raw buffer passed to assembly code
4. **Event Loop**: Standard Cocoa application run loop

## Building for Different Targets

The code is specifically designed for:
- **Architecture**: ARM64 (AArch64)
- **OS**: macOS 11.0+
- **ABI**: Apple Silicon calling convention

The assembly uses the macOS/iOS function naming convention with leading underscore (`_mandelbrot_point`).

## Testing

On ARM64 macOS, the application should:
1. Launch a window titled "Mandelbrot Set - ARM64"
2. Display the classic Mandelbrot set with:
   - Main cardioid visible (centered)
   - Circular bulb to the left
   - Colorful gradients showing iteration counts
   - Black interior (points in the set)
3. Render in under 1 second for 800x600 resolution

## Coordinate System

Default view shows the classic Mandelbrot region:
- **X (Real)**: -2.5 to 1.0 (3.5 unit range)
- **Y (Imaginary)**: -1.0 to 1.0 (2.0 unit range)

This captures the main features:
- Large cardioid (centered around origin)
- Circular bulb (at approximately -1.0, 0)
- Interesting fractal detail in the boundary region
