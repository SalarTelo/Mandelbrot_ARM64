// Mandelbrot Set Computation in ARM64 Assembly
// Function: mandelbrot_point
// Computes the Mandelbrot iteration count for a single point
// Parameters:
//   d0 - real part (x coordinate)
//   d1 - imaginary part (y coordinate)
//   w0 - max iterations
// Returns:
//   w0 - iteration count

.global _mandelbrot_point
.align 2

_mandelbrot_point:
    // Save max_iter parameter
    mov     w9, w0                  // w9 = max_iter
    
    // Initialize variables
    fmov    d2, d0                  // d2 = c_real (x)
    fmov    d3, d1                  // d3 = c_imag (y)
    fmov    d4, #0.0                // d4 = z_real = 0.0
    fmov    d5, #0.0                // d5 = z_imag = 0.0
    fmov    d6, #4.0                // d6 = 4.0 (escape radius squared)
    mov     w0, #0                  // w0 = iteration counter
    
iteration_loop:
    // Check if we've reached max iterations
    cmp     w0, w9
    b.ge    done
    
    // Calculate z_real^2
    fmul    d7, d4, d4              // d7 = z_real * z_real
    
    // Calculate z_imag^2
    fmul    d8, d5, d5              // d8 = z_imag * z_imag
    
    // Check escape condition: z_real^2 + z_imag^2 >= 4.0
    fadd    d10, d7, d8             // d10 = z_real^2 + z_imag^2
    fcmp    d10, d6
    b.ge    done
    
    // Calculate new z_imag = 2 * z_real * z_imag + c_imag
    fmul    d11, d4, d5             // d11 = z_real * z_imag
    fadd    d11, d11, d11           // d11 = 2 * z_real * z_imag
    fadd    d5, d11, d3             // z_imag = 2 * z_real * z_imag + c_imag
    
    // Calculate new z_real = z_real^2 - z_imag^2 + c_real
    fsub    d4, d7, d8              // d4 = z_real^2 - z_imag^2
    fadd    d4, d4, d2              // z_real = z_real^2 - z_imag^2 + c_real
    
    // Increment iteration counter
    add     w0, w0, #1
    b       iteration_loop
    
done:
    ret

// Function: mandelbrot_compute
// Computes Mandelbrot set for entire image buffer
// Parameters:
//   x0 - pointer to output buffer (32-bit RGBA pixels)
//   w1 - width
//   w2 - height
//   d0 - x_min
//   d1 - x_max
//   d2 - y_min
//   d3 - y_max
//   w3 - max_iterations

.global _mandelbrot_compute
.align 2

_mandelbrot_compute:
    // Save callee-saved registers
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     d8, d9, [sp, #-16]!
    stp     d10, d11, [sp, #-16]!
    stp     d12, d13, [sp, #-16]!
    stp     d14, d15, [sp, #-16]!
    
    mov     x29, sp
    
    // Save parameters
    mov     x19, x0                 // x19 = buffer pointer
    mov     w20, w1                 // w20 = width
    mov     w21, w2                 // w21 = height
    mov     w22, w3                 // w22 = max_iterations
    
    // Save coordinate ranges
    fmov    d8, d0                  // d8 = x_min
    fmov    d9, d1                  // d9 = x_max
    fmov    d10, d2                 // d10 = y_min
    fmov    d11, d3                 // d11 = y_max
    
    // Calculate step sizes
    fsub    d12, d9, d8             // d12 = x_max - x_min
    scvtf   d13, w20                // d13 = (double)width
    fdiv    d12, d12, d13           // d12 = x_step
    
    fsub    d13, d11, d10           // d13 = y_max - y_min
    scvtf   d14, w21                // d14 = (double)height
    fdiv    d13, d13, d14           // d13 = y_step
    
    mov     w23, #0                 // w23 = y (row counter)
    
row_loop:
    cmp     w23, w21
    b.ge    compute_done
    
    mov     w24, #0                 // w24 = x (column counter)
    
col_loop:
    cmp     w24, w20
    b.ge    next_row
    
    // Calculate real part: x_coord = x_min + x * x_step
    scvtf   d0, w24                 // d0 = (double)x
    fmul    d0, d0, d12             // d0 = x * x_step
    fadd    d0, d0, d8              // d0 = x_min + x * x_step
    
    // Calculate imaginary part: y_coord = y_min + y * y_step
    scvtf   d1, w23                 // d1 = (double)y
    fmul    d1, d1, d13             // d1 = y * y_step
    fadd    d1, d1, d10             // d1 = y_min + y * y_step
    
    // Call mandelbrot_point
    mov     w0, w22                 // w0 = max_iterations
    bl      _mandelbrot_point
    
    // Convert iteration count to color
    // w0 now contains the iteration count
    cmp     w0, w22
    b.ge    black_pixel             // If reached max iterations, make it black
    
    // Color based on iteration count (simple gradient)
    lsl     w1, w0, #2              // w1 = iter * 4
    and     w1, w1, #0xFF           // w1 = R component
    
    lsl     w2, w0, #3              // w2 = iter * 8
    and     w2, w2, #0xFF           // w2 = G component
    
    lsl     w3, w0, #4              // w3 = iter * 16
    and     w3, w3, #0xFF           // w3 = B component
    
    b       write_pixel
    
black_pixel:
    mov     w1, #0                  // R = 0
    mov     w2, #0                  // G = 0
    mov     w3, #0                  // B = 0
    
write_pixel:
    // Calculate pixel offset: offset = (y * width + x) * 4
    mul     w4, w23, w20            // w4 = y * width
    add     w4, w4, w24             // w4 = y * width + x
    lsl     w4, w4, #2              // w4 = (y * width + x) * 4
    
    // Write RGBA pixel (format: RGBA)
    strb    w1, [x19, w4, sxtw]     // Write R
    add     w5, w4, #1
    strb    w2, [x19, w5, sxtw]     // Write G
    add     w5, w4, #2
    strb    w3, [x19, w5, sxtw]     // Write B
    add     w5, w4, #3
    mov     w6, #0xFF
    strb    w6, [x19, w5, sxtw]     // Write A (255 = opaque)
    
    add     w24, w24, #1            // x++
    b       col_loop
    
next_row:
    add     w23, w23, #1            // y++
    b       row_loop
    
compute_done:
    // Restore callee-saved registers
    ldp     d14, d15, [sp], #16
    ldp     d12, d13, [sp], #16
    ldp     d10, d11, [sp], #16
    ldp     d8, d9, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    
    ret
