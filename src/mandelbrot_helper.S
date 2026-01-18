
.section __DATA,__data
.p2align 3

mh_const_half:      .double 0.5
mh_const_ln2:       .double 0.6931471805599453
mh_const_one:       .double 1.0

// Color frequency: higher = more repeating bands
mh_const_freq:      .double 6.0
mh_const_speed:     .double 4.0

.section __TEXT,__text
.p2align 2
.globl _mandelbrot_compute_smooth_color
.extern _log
.extern g_palette
.extern g_time

// Function: Compute smooth color via Palette Lookup
//
// Inputs:
//   d0 = magnitude squared (z_real^2 + z_imag^2)
//   w8 = iteration count
// Output:
//   w12 = Packed AABBGGRR color
//
// Clobbers: d0-d7, d14, x0, x9, x10 (and LR)
_mandelbrot_compute_smooth_color:
    stp     x30, x29, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #16
    stp     w8, w16, [sp]              // Save iter

    // 1. Calculate smooth value 'mu'
    // mu = iter + 1 - log2(log(|z|))
    //    = iter + 1 - log2(0.5 * log(mag2))
    //    = iter + 1 - (log(0.5 * log(mag2)) / ln2)

    bl      _log                       // log(mag2)
    adrp    x0, mh_const_half@PAGE
    ldr     d7, [x0, mh_const_half@PAGEOFF]
    fmul    d0, d0, d7                 // 0.5 * log(mag2)
    
    // Safety: if d0 <= 0 (shouldn't happen for escaped points), clamp
    fcmp    d0, #0.0
    b.gt    .L_log_ok
    fmov    d0, #1.0                   // fallback
.L_log_ok:
    bl      _log                       // log(log|z|)
    
    adrp    x0, mh_const_ln2@PAGE
    ldr     d7, [x0, mh_const_ln2@PAGEOFF]
    fdiv    d0, d0, d7                 // / ln2  --> log2(log|z|)

    ldp     w8, w16, [sp]
    scvtf   d6, w8                     // iter
    adrp    x0, mh_const_one@PAGE
    ldr     d14, [x0, mh_const_one@PAGEOFF]
    fadd    d6, d6, d14                // iter + 1
    fsub    d6, d6, d0                 // mu = iter + 1 - log2...

    // 2. Palette Lookup with Animation
    // val = mu * freq + time * speed
    adrp    x0, mh_const_freq@PAGE
    ldr     d7, [x0, mh_const_freq@PAGEOFF]
    fmul    d6, d6, d7                 // mu * freq
    
    // Add time offset
    adrp    x0, g_time@PAGE
    ldr     s5, [x0, g_time@PAGEOFF]
    fcvt    d5, s5
    adrp    x0, mh_const_speed@PAGE
    ldr     d7, [x0, mh_const_speed@PAGEOFF]
    fmul    d5, d5, d7                 // time * speed
    fadd    d6, d6, d5                 // val + offset

    fcvtzs  w9, d6                     // Convert to int
    
    and     w9, w9, #0xFF              // Modulo 256
    
    adrp    x0, g_palette@PAGE
    add     x0, x0, g_palette@PAGEOFF
    ldr     w12, [x0, x9, lsl #2]      // Load color

    add     sp, sp, #16
    ldp     x30, x29, [sp], #16
    ret
