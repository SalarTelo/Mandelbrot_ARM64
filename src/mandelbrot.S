//------------------------------------------------------------------------------
// mandelbrot renderer (AArch64)
//
// this is the heavy lifting:
//   - split work into row bands for threads
//   - SIMD paths for speed (2 pixels at a time)
//   - smooth coloring via log/log
//   - scalar fallback for leftovers
//------------------------------------------------------------------------------

.section __TEXT,__text
.p2align 2

.extern g_center_x_frame
.extern g_center_y_frame
.extern g_zoom_frame
.extern g_thread_count
.extern _pthread_create
.extern _pthread_join
.extern _log
.extern g_max_iter_frame
.extern _mandelbrot_compute_smooth_color

.equ MAX_ITER,    500
.equ MAX_THREADS, 10

// worker arg layout (aligned for doubles)
.equ ARG_FB,     0    // uint32_t*
.equ ARG_W,      8    // int
.equ ARG_H,      12   // int
.equ ARG_STRIDE, 16   // int
.equ ARG_Y0,     20   // int
.equ ARG_Y1,     24   // int
.equ ARG_IDX,    28   // int (unused)
.equ ARG_PAD,    32   // 4-byte pad (unused)
.equ ARG_CX,     40   // double
.equ ARG_CY,     48   // double
.equ ARG_ZOOM,   56   // double
.equ ARG_SIZE,   64
.equ THREAD_BYTES, MAX_THREADS * 8
.equ ARGS_BYTES,   MAX_THREADS * ARG_SIZE
.equ MT_LOCAL_SIZE, THREAD_BYTES + ARGS_BYTES

//------------------------------------------------------------------------------
// double literals (shared across scalar + SIMD paths)
//------------------------------------------------------------------------------
.section __DATA,__data
.p2align 3
mand_const_three:     .double 3.0
mand_const_four:      .double 4.0
mand_const_two:       .double 2.0
mand_const_quarter:   .double 0.25
mand_const_sixteenth: .double 0.0625
mand_const_one:       .double 1.0
.section __TEXT,__text
.p2align 2


//------------------------------------------------------------------------------
// public entry points
//------------------------------------------------------------------------------
.globl _mandelbrot_render
// calculate how many threads to spawn,
// divide the screen height by that number, and launch the threads.
_mandelbrot_render:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x27, x28, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #MT_LOCAL_SIZE
    add     x28, sp, #THREAD_BYTES       // This is where our thread arguments live on the stack

    // Arguments
    mov     x19, x0      // fb
    mov     w20, w1      // width
    mov     w21, w2      // height
    mov     w22, w3      // stride
    cbz     w20, .L_mt_done
    cbz     w21, .L_mt_done

    // snapshot params (double)
    adrp    x0, g_center_x_frame@PAGE
    ldr     d0, [x0, g_center_x_frame@PAGEOFF]
    adrp    x0, g_center_y_frame@PAGE
    ldr     d1, [x0, g_center_y_frame@PAGEOFF]
    adrp    x0, g_zoom_frame@PAGE
    ldr     d2, [x0, g_zoom_frame@PAGEOFF]

    // thread_count = clamp(g_thread_count,1,MAX_THREADS,height)
    adrp    x0, g_thread_count@PAGE
    ldr     w23, [x0, g_thread_count@PAGEOFF]
    cbnz    w23, .L_tc_ok
    mov     w23, #1
.L_tc_ok:
    mov     w24, #MAX_THREADS
    cmp     w23, w24
    csel    w23, w23, w24, le
    cmp     w23, w21
    csel    w23, w23, w21, le

    // base = height / tc, rem = height % tc
    udiv    w24, w21, w23
    msub    w25, w24, w23, w21   // rem

    mov     w26, #0              // current y
    mov     w27, #0              // i

.L_mt_spawn:
    cmp     w27, w23
    b.ge    .L_mt_join

    // args ptr
    mov     w8, #ARG_SIZE
    madd    x9, x27, x8, x28

    // rows for this thread
    mov     w12, w24
    cmp     w27, w25
    cinc    w12, w12, lt

    // fill args
    str     x19, [x9, #ARG_FB]
    str     w20, [x9, #ARG_W]
    str     w21, [x9, #ARG_H]
    str     w22, [x9, #ARG_STRIDE]
    str     w26, [x9, #ARG_Y0]
    add     w14, w26, w12
    str     w14, [x9, #ARG_Y1]
    str     d0, [x9, #ARG_CX]
    str     d1, [x9, #ARG_CY]
    str     d2, [x9, #ARG_ZOOM]
    add     w26, w26, w12

    // pthread_create(&threads[i], NULL, worker, args)
    add     x0, sp, x27, lsl #3
    mov     x1, #0
    adrp    x2, _mandelbrot_worker@PAGE
    add     x2, x2, _mandelbrot_worker@PAGEOFF
    mov     x3, x9
    bl      _pthread_create
    cbz     w0, .L_mt_spawn_next
    // If create fails, run inline
    mov     w8, #ARG_SIZE
    madd    x9, x27, x8, x28
    mov     x0, x9
    bl      _mandelbrot_worker
    mov     x0, #0
    str     x0, [sp, x27, lsl #3]

.L_mt_spawn_next:
    add     w27, w27, #1
    b       .L_mt_spawn

.L_mt_join:
    mov     w27, #0
.L_mt_join_loop:
    cmp     w27, w23
    b.ge    .L_mt_done
    add     x0, sp, x27, lsl #3
    ldr     x0, [x0]
    cbz     x0, .L_mt_join_next
    mov     x1, #0
    bl      _pthread_join
.L_mt_join_next:
    add     w27, w27, #1
    b       .L_mt_join_loop

.L_mt_done:
    add     sp, sp, #MT_LOCAL_SIZE
    ldp     x27, x28, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret


// render_rows: worker for a band of rows (y_start..y_end).
// keep constants in callee-saved vectors so _log doesn't trash them.
_mandelbrot_render_rows:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x27, x28, [sp, #-16]!
    stp     q8, q9, [sp, #-32]!
    stp     q10, q11, [sp, #-32]!
    stp     q12, q13, [sp, #-32]!
    stp     q14, q15, [sp, #-32]!
    mov     x29, sp
    sub     sp, sp, #32              // local slots (max_iter + temp padding)

    // args
    mov     x19, x0        // fb base
    mov     w20, w1        // width
    mov     w21, w2        // height
    uxtw    x22, w3        // stride bytes
    mov     w23, w4        // y_start
    mov     w24, w5        // y_end
    cbz     w20, .L_rows_done
    cbz     w21, .L_rows_done

    // clamp y to [0, height]
    cmp     w23, wzr
    csel    w23, w23, wzr, ge
    cmp     w24, w21
    csel    w24, w24, w21, le
    cmp     w23, w24
    b.ge    .L_rows_done

    // params (keep in callee-saved v8-v10 across _log calls)
    fmov    d8, d0         // center_x
    fmov    d9, d1         // center_y
    fmov    d10, d2        // zoom

    // constants (keep in callee-saved v11-v14)
    adrp    x0, mand_const_three@PAGE
    ldr     d11, [x0, mand_const_three@PAGEOFF] // 3.0
    adrp    x0, mand_const_four@PAGE
    ldr     d12, [x0, mand_const_four@PAGEOFF]  // 4.0
    adrp    x0, mand_const_two@PAGE
    ldr     d13, [x0, mand_const_two@PAGEOFF]   // 2.0
    adrp    x0, mand_const_one@PAGE
    ldr     d14, [x0, mand_const_one@PAGEOFF]   // 1.0

    // grab the per-frame max iter; fall back to 500 if it's zero
    adrp    x0, g_max_iter_frame@PAGE
    ldr     w16, [x0, g_max_iter_frame@PAGEOFF]
    cbnz    w16, .L_max_iter_ok
    mov     w16, #MAX_ITER
.L_max_iter_ok:
    str     w16, [x29, #-16]

    adrp    x0, mand_const_quarter@PAGE
    ldr     d6, [x0, mand_const_quarter@PAGEOFF]   // 0.25
    adrp    x0, mand_const_sixteenth@PAGE
    ldr     d7, [x0, mand_const_sixteenth@PAGEOFF] // 0.0625
    mov     w28, #0
    movk    w28, #0xFF00, lsl #16                 // 0xFF000000

    // scale = (3.0 / width) * zoom (keep in callee-saved d15)
    scvtf   d0, w20
    fdiv    d15, d11, d0
    fmul    d15, d15, d10

    // SIMD constants
    dup     v20.2d, v15.d[0]  // scale
    dup     v21.2d, v12.d[0]  // 4.0
    dup     v22.2d, v13.d[0]  // 2.0
    dup     v23.2d, v6.d[0]   // 0.25
    dup     v24.2d, v7.d[0]   // 0.0625

    lsr     w25, w20, #1   // half width
    lsr     w26, w21, #1   // half height

.L_row_loop:
    cmp     w23, w24
    b.ge    .L_rows_done

    // row_ptr = fb + y * stride
    madd    x9, x23, x22, x19

    // cy = (h/2 - y) * scale_y + center_y
    sub     w8, w26, w23
    scvtf   d0, w8
    fmul    d0, d0, d15
    fadd    d27, d0, d9        // cy in d27

    mov     w27, wzr           // x = 0
.L_col_loop:
    cmp     w27, w20
    b.ge    .L_next_row

    add     w14, w27, #3
    cmp     w14, w20
    b.ge    .L_col_scalar

    // reload SIMD constants (clobbered by _log)
    adrp    x0, mand_const_quarter@PAGE
    ldr     d6, [x0, mand_const_quarter@PAGEOFF]
    adrp    x0, mand_const_sixteenth@PAGE
    ldr     d7, [x0, mand_const_sixteenth@PAGEOFF]
    dup     v20.2d, v15.d[0]  // scale
    dup     v21.2d, v12.d[0]  // 4.0
    dup     v22.2d, v13.d[0]  // 2.0
    dup     v23.2d, v6.d[0]   // 0.25
    dup     v24.2d, v7.d[0]   // 0.0625

    // pair A (pixels 0, 1) -> v18(zx), v19(zy), v26(iter), v16(cx), v25(mask)
    sub     w8, w27, w25      // col - half_width
    scvtf   d0, w8
    add     w14, w27, #1
    sub     w14, w14, w25
    scvtf   d1, w14
    ins     v16.d[0], v0.d[0]
    ins     v16.d[1], v1.d[0]
    fmul    v16.2d, v16.2d, v20.2d   // cx raw
    dup     v17.2d, v8.d[0]          // center_x
    fadd    v16.2d, v16.2d, v17.2d   // cx_A

    // pair B (pixels 2, 3) -> v2(zx), v3(zy), v4(iter), v6(cx), v5(mask)
    add     w14, w27, #2
    sub     w14, w14, w25
    scvtf   d0, w14
    add     w14, w27, #3
    sub     w14, w14, w25
    scvtf   d1, w14
    ins     v6.d[0], v0.d[0]
    ins     v6.d[1], v1.d[0]
    fmul    v6.2d, v6.2d, v20.2d    // cx raw
    fadd    v6.2d, v6.2d, v17.2d    // cx_B

    // init Z and shared Y
    dup     v17.2d, v27.d[0]          // cy (shared)
    
    eor     v18.16b, v18.16b, v18.16b // zx_A = 0
    eor     v19.16b, v19.16b, v19.16b // zy_A = 0
    eor     v2.16b, v2.16b, v2.16b    // zx_B = 0
    eor     v3.16b, v3.16b, v3.16b    // zy_B = 0
    eor     v26.16b, v26.16b, v26.16b // iter_A = 0
    eor     v4.16b, v4.16b, v4.16b    // iter_B = 0
    movi    v25.16b, #0xFF            // mask_A = active
    movi    v5.16b, #0xFF             // mask_B = active

    mov     w10, #0
.L_iter_simd_unrolled:
    cmp     w10, w16
    b.ge    .L_iter_simd_unrolled_done

    // Unrolled Body (Interleaved)
    // A uses: v18(zx), v19(zy), v16(cx), v17(cy)
    // B uses: v2(zx), v3(zy), v6(cx), v17(cy)

    // 1. Compute Squares
    fmul    v0.2d, v18.2d, v18.2d     // A: zx^2
    fmul    v1.2d, v19.2d, v19.2d     // A: zy^2
    fmul    v7.2d, v2.2d, v2.2d       // B: zx^2
    fmul    v28.2d, v3.2d, v3.2d      // B: zy^2 (v28 scratch)

    // 2. Check Escape (Mag2 > 4.0)
    fadd    v29.2d, v0.2d, v1.2d      // A: mag2
    fadd    v30.2d, v7.2d, v28.2d     // B: mag2
    fcmle   v29.2d, v29.2d, v21.2d    // A: <= 4.0 ?
    fcmle   v30.2d, v30.2d, v21.2d    // B: <= 4.0 ?
    
    // 3. Update Masks
    and     v25.16b, v25.16b, v29.16b // A: update active
    and     v5.16b, v5.16b, v30.16b   // B: update active
    
    // 4. Early Exit Check (if BOTH masks are empty)
    orr     v29.16b, v25.16b, v5.16b
    umaxv   b31, v29.16b
    umov    w8, v31.b[0]
    cbz     w8, .L_iter_simd_unrolled_done

    // 5. Compute ZY New = 2*zx*zy + cy
    fmul    v29.2d, v18.2d, v19.2d    // A: zx*zy
    fmul    v30.2d, v2.2d, v3.2d      // B: zx*zy
    fmul    v29.2d, v29.2d, v22.2d    // A: * 2.0
    fmul    v30.2d, v30.2d, v22.2d    // B: * 2.0
    fadd    v29.2d, v29.2d, v17.2d    // A: + cy
    fadd    v30.2d, v30.2d, v17.2d    // B: + cy (new zy pending)

    // 6. Compute ZX New = zx^2 - zy^2 + cx
    fsub    v0.2d, v0.2d, v1.2d       // A: zx^2 - zy^2
    fsub    v7.2d, v7.2d, v28.2d      // B: zx^2 - zy^2
    fadd    v0.2d, v0.2d, v16.2d      // A: + cx (new zx pending)
    fadd    v7.2d, v7.2d, v6.2d       // B: + cx (new zx pending)

    // 7. Store / Select based on Mask (Stickiness)
    
    // A: Update ZY
    bic     v31.16b, v19.16b, v25.16b // old & ~mask
    and     v19.16b, v29.16b, v25.16b // new & mask
    orr     v19.16b, v19.16b, v31.16b // combine
    // A: Update ZX
    bic     v31.16b, v18.16b, v25.16b
    and     v18.16b, v0.16b, v25.16b
    orr     v18.16b, v18.16b, v31.16b

    // B: Update ZY
    bic     v31.16b, v3.16b, v5.16b
    and     v3.16b, v30.16b, v5.16b
    orr     v3.16b, v3.16b, v31.16b
    // B: Update ZX
    bic     v31.16b, v2.16b, v5.16b
    and     v2.16b, v7.16b, v5.16b
    orr     v2.16b, v2.16b, v31.16b
    
    // 8. Increment Iteration Counts
    // Active lanes get +1.
    ushr    v0.2d, v25.2d, #63        // A: active -> 1/0
    ushr    v1.2d, v5.2d, #63         // B: active -> 1/0
    xtn     v0.2s, v0.2d
    xtn     v1.2s, v1.2d
    add     v26.2s, v26.2s, v0.2s     // A: iter += 1
    add     v4.2s, v4.2s, v1.2s       // B: iter += 1

    add     w10, w10, #1
    b       .L_iter_simd_unrolled

.L_iter_simd_unrolled_done:
    // Create combined inside masks for styling (if iter >= max, set mask)
    dup     v30.2s, w16
    cmge    v31.2s, v26.2s, v30.2s     // A: iter >= max
    mov     v29.16b, v31.16b           // A: inside mask
    cmge    v31.2s, v4.2s, v30.2s      // B: iter >= max
    mov     v5.16b, v31.16b            // B: inside mask

    // SAVE STACK (144 bytes) for 8 vectors + row_ptr
    sub     sp, sp, #144
    
    // Pair A
    st1     {v18.2d, v19.2d}, [sp], #32 // 00-31: zx_A, zy_A
    str     q26, [sp]                   // 32-47: iter_A
    str     q29, [sp, #16]              // 48-63: mask_A
    add     sp, sp, #32

    // Pair B
    st1     {v2.2d, v3.2d}, [sp], #32   // 64-95: zx_B, zy_B
    str     q4, [sp]                    // 96-111: iter_B
    str     q5, [sp, #16]               // 112-127: mask_B
    add     sp, sp, #32

    str     x9, [sp]                    // 128: row_ptr
    // Reset sp to base
    sub     sp, sp, #128

    // Process 4 Lanes (0..3)
    mov     x28, #0                    // Lane index
.L_simd_unrolled_lane_loop:
    cmp     x28, #4
    b.ge    .L_simd_unrolled_lanes_done

    // Determine which pair (0/1 -> A, 2/3 -> B)
    // A: offsets 0..63
    // B: offsets 64..127
    // Lane mask bits: 0,1 -> 0; 2,3 -> 1
    tst     x28, #2                    // Check bit 1 (values 2,3)
    b.ne    .L_lane_pair_B
    
.L_lane_pair_A:
    mov     x13, #0                    // Base offset A
    and     x14, x28, #1               // Sub-lane (0 or 1)
    b       .L_lane_load
    
.L_lane_pair_B:
    mov     x13, #64                   // Base offset B
    and     x14, x28, #1               // Sub-lane
    
.L_lane_load:
    // Load Mask
    add     x12, sp, x13               // Base
    add     x12, x12, #48              // Mask offset within pair (16+16+16)
    ldr     w8, [x12, x14, lsl #2]
    cbnz    w8, .L_lane_inside

    // Load iter
    add     x12, sp, x13
    add     x12, x12, #32              // Iter offset
    ldr     w8, [x12, x14, lsl #2]
    
    // Load zx, zy
    add     x12, sp, x13               // zx base
    ldr     d0, [x12, x14, lsl #3]
    add     x12, x12, #16              // zy base
    ldr     d1, [x12, x14, lsl #3]

    // mag2
    fmul    d0, d0, d0
    fmul    d1, d1, d1
    fadd    d0, d0, d1

    // Call helper
    bl      _mandelbrot_compute_smooth_color
    b       .L_lane_store

.L_lane_inside:
    mov     w12, #0
    movk    w12, #0xFF00, lsl #16      // Black

.L_lane_store:
    ldr     x9, [sp, #128]             // reload row ptr
    add     x10, x9, x27, lsl #2       // addr = row + col*4
    str     w12, [x10, x28, lsl #2]    // store at addr + lane*4

    add     x28, x28, #1
    b       .L_simd_unrolled_lane_loop

.L_simd_unrolled_lanes_done:
    add     sp, sp, #144
    add     w27, w27, #4
    b       .L_col_loop

.L_col_scalar:
    // Scalar tail (single pixel)
    add     x10, x9, x27, lsl #2

    // cx = (x - w/2) * scale_x + center_x
    sub     w8, w27, w25
    scvtf   d0, w8
    fmul    d0, d0, d15
    fadd    d28, d0, d8        // cx in d28

    // Reload inside-test constants (scalar path clobbers d6/d7 later).
    adrp    x0, mand_const_quarter@PAGE
    ldr     d6, [x0, mand_const_quarter@PAGEOFF]   // 0.25
    adrp    x0, mand_const_sixteenth@PAGE
    ldr     d7, [x0, mand_const_sixteenth@PAGEOFF] // 0.0625

    // Analytic inside tests (cardioid + period-2 bulb)
    fsub    d0, d28, d6               // x - 0.25
    fmul    d1, d0, d0
    fmul    d2, d27, d27              // y^2
    fadd    d3, d1, d2                // q
    fadd    d4, d3, d0
    fmul    d5, d3, d4
    fmul    d30, d2, d6               // 0.25*y^2
    fcmp    d5, d30
    b.le    .L_inside
    adrp    x0, mand_const_one@PAGE
    ldr     d14, [x0, mand_const_one@PAGEOFF]
    fadd    d0, d28, d14              // x + 1
    fmul    d1, d0, d0
    fadd    d1, d1, d2
    fcmp    d1, d7                    // <= 1/16 ?
    b.le    .L_inside

    // Iterate until escape (|z|^2 > 4).

    // Iterate z = z^2 + c (start at z0 = 0)
    fmov    d1, xzr            // zx = 0
    fmov    d2, xzr            // zy = 0
    mov     w8, wzr            // iter = 0
.L_iter_loop:
    cmp     w8, w16
    b.ge    .L_inside          // treat as inside when maxed out
    // Step 1
    fmul    d3, d1, d1         // zx^2
    fmul    d4, d2, d2         // zy^2
    fadd    d5, d3, d4         // mag2
    fcmp    d5, d12            // > 4.0 ?
    b.gt    .L_iter_done_scalar_smooth

    // zy = 2*zx*zy + cy
    fmul    d6, d1, d2
    fmul    d6, d6, d13
    fadd    d2, d6, d27
    // zx = zx^2 - zy^2 + cx
    fsub    d1, d3, d4
    fadd    d1, d1, d28

    add     w8, w8, #1
    cmp     w8, w16
    b.ge    .L_inside

    // Step 2
    fmul    d3, d1, d1
    fmul    d4, d2, d2
    fadd    d5, d3, d4
    fcmp    d5, d12
    b.gt    .L_iter_done_scalar_smooth

    fmul    d6, d1, d2
    fmul    d6, d6, d13
    fadd    d2, d6, d27
    fsub    d1, d3, d4
    fadd    d1, d1, d28

    add     w8, w8, #1
    b       .L_iter_loop

.L_iter_done_scalar_smooth:
    sub     sp, sp, #32
    str     x9, [sp]
    str     x10, [sp, #8]
    // Call helper
    // d5 = mag2, w8 = iter
    fmov    d0, d5
    bl      _mandelbrot_compute_smooth_color
    
    ldr     x10, [sp, #8]
    ldr     x9, [sp]
    add     sp, sp, #32

    str     w12, [x10]


    add     w27, w27, #1
    b       .L_col_loop

.L_inside:
    str     w28, [x10]      // solid black
    add     w27, w27, #1
    b       .L_col_loop

.L_next_row:
    add     w23, w23, #1
    b       .L_row_loop

.L_rows_done:
    add     sp, sp, #32
    ldp     q14, q15, [sp], #32
    ldp     q12, q13, [sp], #32
    ldp     q10, q11, [sp], #32
    ldp     q8, q9, [sp], #32
    ldp     x27, x28, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret



//------------------------------------------------------------------------------


// pthreads calls this generic function. We need to unpack our specific arguments (framebuffer pointer, coordinates)
// and then jump into the actual rendering logic.
_mandelbrot_worker:
    stp     x29, x30, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    mov     x29, sp

    // Unpack arguments from struct
    mov     x19, x0
    ldr     x0, [x19, #ARG_FB]
    ldr     w1, [x19, #ARG_W]
    ldr     w2, [x19, #ARG_H]
    ldr     w3, [x19, #ARG_STRIDE]
    uxtw    x22, w3
    ldr     w20, [x19, #ARG_Y0]
    ldr     w21, [x19, #ARG_Y1]

    // Clamp rows to valid range [0, height]
    cmp     w20, wzr
    csel    w20, w20, wzr, ge
    cmp     w21, w2
    csel    w21, w21, w2, le
    cmp     w20, w21
    b.ge    .L_worker_ret

    // Load up the floating point parameters (zoom, center)
    ldr     d0, [x19, #ARG_CX]
    ldr     d1, [x19, #ARG_CY]
    ldr     d2, [x19, #ARG_ZOOM]
    
    // Kick off the rendering for this horizontal strip
    mov     w4, w20
    mov     w5, w21
    bl      _mandelbrot_render_rows

.L_worker_ret:
    mov     x0, #0
    ldp     x19, x20, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x29, x30, [sp], #16
    ret
