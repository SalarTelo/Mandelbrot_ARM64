# Example Output

When the application runs successfully on ARM64 macOS, you should see:

## Window

A native macOS window with:
- Title: "Mandelbrot Set - ARM64"
- Dimensions: 800x600 pixels
- Standard macOS window controls (close, minimize, zoom)

## Visual Output

The Mandelbrot set visualization displays:

### Main Features

1. **Main Cardioid (Center)**
   - The largest dark region in the center
   - Roughly heart-shaped
   - Represents points that converge very slowly

2. **Circular Bulb (Left)**
   - Large circular dark region to the left of center
   - Centered approximately at (-1.0, 0) in the complex plane

3. **Fractal Boundary**
   - Intricate, infinitely complex boundary
   - Colored bands showing iteration counts
   - Self-similar structures at all scales

4. **Color Gradient**
   - Points outside the set: Colored (red, green, blue gradients)
   - Points inside the set: Black
   - Brighter colors indicate faster divergence
   - Darker colors (closer to black) indicate slower divergence

### Expected Coordinate Coverage

With default settings:
- **X-axis (horizontal)**: -2.5 to 1.0
- **Y-axis (vertical)**: -1.0 to 1.0

This captures the classic "full view" of the Mandelbrot set.

## Console Output

When launching from terminal, you should see:

```
Computing Mandelbrot set (800x600)...
Computation complete!
```

## Performance

On Apple Silicon (M1/M2/M3):
- Computation time: < 1 second for 800x600
- Window appears immediately
- No noticeable lag or stuttering

## Example Regions of Interest

For future exploration (requires modifying X_MIN, X_MAX, Y_MIN, Y_MAX):

1. **Seahorse Valley**: x: -0.75 to -0.735, y: 0.095 to 0.11
2. **Elephant Valley**: x: 0.25 to 0.35, y: 0 to 0.05
3. **Spiral**: x: -0.75 to -0.74, y: 0.09 to 0.11
4. **Dendrite**: x: -0.16 to -0.15, y: 1.03 to 1.045

## Troubleshooting

If the window appears but is blank or all black:
- Check that the buffer allocation succeeded
- Verify assembly function is being called correctly
- Check console for error messages

If colors seem wrong:
- Verify RGBA byte order in assembly
- Check color calculation in `write_pixel` section
- Ensure alpha channel is set to 0xFF (opaque)

If the application crashes:
- Check stack alignment in assembly
- Verify register preservation (callee-saved registers)
- Check buffer bounds in pixel writing
