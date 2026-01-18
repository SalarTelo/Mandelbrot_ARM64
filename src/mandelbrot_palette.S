
.section __DATA,__data
.p2align 4
// The Color Palette (256 entries * 4 bytes = 1024 bytes)
.globl g_palette
g_palette: 
    .space 1024

// Constants for cosine palette generation
// We want a classic smooth gradient.
// Formula: c = a + b * cos(2*pi * (t + d))
// param a = 0.5 (127.5)
// param b = 0.5 (127.5)
// param d: R=0.0, G=0.33, B=0.67 (triadic) or customized

pal_const_scale: .double 100.0
pal_const_mid:   .double 155.0
pal_const_2pi:   .double 6.28318530718
pal_const_inv256: .double 0.00390625  // 1/256

// Phases for R, G, B
// Dominant Cyan/Turquoise: Green and Blue aligned.
// Red shifted away to create white highlights only at peaks.
pal_phase_r: .double 0.80
pal_phase_g: .double 0.00
pal_phase_b: .double 0.10

.section __TEXT,__text
.p2align 2
.globl _palette_init
.extern _cos

//------------------------------------------------------------------------------
// Generates the 256-color lookup table at runtime.
// No arguments.
//------------------------------------------------------------------------------
_palette_init:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     d8, d9, [sp, #-16]!
    stp     d10, d11, [sp, #-16]!
    mov     x29, sp

    // Preload constants
    adrp    x0, pal_const_scale@PAGE
    ldr     d8, [x0, pal_const_scale@PAGEOFF]    // scale = 127.5
    
    adrp    x0, pal_const_mid@PAGE
    ldr     d9, [x0, pal_const_mid@PAGEOFF]      // mid = 127.5
    
    adrp    x0, pal_const_2pi@PAGE
    ldr     d10, [x0, pal_const_2pi@PAGEOFF]     // 2*pi
    
    adrp    x0, pal_const_inv256@PAGE
    ldr     d11, [x0, pal_const_inv256@PAGEOFF]  // 1.0/256.0

    // Loop i from 0 to 255
    mov     w19, #0   // i
    adrp    x20, g_palette@PAGE
    add     x20, x20, g_palette@PAGEOFF

.L_pal_loop:
    cmp     w19, #256
    b.ge    .L_pal_done

    // t = i / 256.0
    scvtf   d0, w19
    fmul    d0, d0, d11      // t in [0, 1)

    // Compute Red: mid + scale * cos(2pi * (t + phase_r))
    adrp    x0, pal_phase_r@PAGE
    ldr     d1, [x0, pal_phase_r@PAGEOFF]
    fadd    d1, d0, d1       // t + phase_r
    fmul    d1, d1, d10      // (t+p)*2pi
    fmov    d0, d1           // arg for cos
    bl      _cos
    fmul    d0, d0, d8       // * scale
    fadd    d0, d0, d9       // + mid
    fcvtzs  w1, d0           // Red Int

    // Compute Green
    scvtf   d0, w19
    fmul    d0, d0, d11
    adrp    x0, pal_phase_g@PAGE
    ldr     d1, [x0, pal_phase_g@PAGEOFF]
    fadd    d1, d0, d1
    fmul    d1, d1, d10
    fmov    d0, d1
    bl      _cos
    fmul    d0, d0, d8
    fadd    d0, d0, d9
    fcvtzs  w2, d0           // Green Int

    // Compute Blue
    scvtf   d0, w19
    fmul    d0, d0, d11
    adrp    x0, pal_phase_b@PAGE
    ldr     d1, [x0, pal_phase_b@PAGEOFF]
    fadd    d1, d0, d1
    fmul    d1, d1, d10
    fmov    d0, d1
    bl      _cos
    fmul    d0, d0, d8
    fadd    d0, d0, d9
    fcvtzs  w3, d0           // Blue Int

    // Pack: AABBGGRR (AA=FF)
    lsl     w4, w3, #16      // B << 16
    orr     w4, w4, w2, lsl #8 // G << 8
    orr     w4, w4, w1       // R
    orr     w4, w4, #0xFF000000 // Alpha

    // Store
    str     w4, [x20, x19, lsl #2]

    add     w19, w19, #1
    b       .L_pal_loop

.L_pal_done:
    ldp     d10, d11, [sp], #16
    ldp     d8, d9, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret
