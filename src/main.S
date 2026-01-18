
//------------------------------------------------------------------------------
// external symbols
//------------------------------------------------------------------------------

// title + handle to the window
.extern window_title
.extern window_handle

// window functions
.extern _window_create
.extern _window_poll_events
.extern _window_should_close
.extern _window_present
.extern _window_destroy

.extern _window_get_mouse_uv_f32
.extern _window_get_time_seconds_f32
.extern _window_get_delta_seconds_f32
.extern _noise_fbm2_f32
.extern _window_get_mouse_button
.extern _mandelbrot_render
.extern _log

.extern _sqrtf
.extern _sinf
.extern _palette_init

//------------------------------------------------------------------------------
// assemble-time constants
//------------------------------------------------------------------------------
.equ SCREEN_WIDTH,    960
.equ SCREEN_HEIGHT,    640
.equ INV_SCREEN_WIDTH, 0x3a888889   // (1.0/960.0)
.equ INV_SCREEN_HEIGHT, 0x3acccccd  // (1.0/640.0)

.equ BYTES_PER_PIXEL,   4

.equ SCREEN_PIXELS,  0x96000    // SCREEN_WIDTH * SCREEN_HEIGHT
.equ SCREEN_ROW_STRIDE, 0xF00   // (SCREEN_WIDTH * BYTES_PER_PIXEL)
.equ SCREEN_BUFF_SIZE, 0x258000 // SCREEN_PIXELS * BYTES_PER_PIXEL


.equ SCREEN_CENTER_PX, SCREEN_WIDTH/2
.equ SCREEN_CENTER_PY, SCREEN_HEIGHT/2

//------------------------------------------------------------------------------
// executable code
//------------------------------------------------------------------------------
.section __TEXT,__text
.p2align 2


// x0   - x18 (caller reserved)
// x19  - x28 (callee reserved)

// main entry point
.globl _main
_main:
    stp x29, x30, [sp, #-16]!
    stp x27, x28, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    mov x29, sp

    // create window with screen dimensions
    mov  x0, SCREEN_WIDTH
    mov  x1, SCREEN_HEIGHT
    bl   _window_create
    cbnz x0, .L_main_ret_error

    // initialize color palette
    bl   _palette_init

.L_main_loop:
    // check if window should close
    bl _window_should_close
    cbnz x0, .L_main_ret

    // poll events and update delta time
    bl _window_poll_events

    // update state (time, input, zoom)
    bl _update_state

    // render the frame
    bl _render_frame

    // present the result
    bl _present_frame

    b .L_main_loop

.L_main_ret_error:
    bl _window_destroy
    mov x0, #-1
.L_main_ret:
    ldp x19, x20, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x25, x26, [sp], #16
    ldp x27, x28, [sp], #16
    ldp x29, x30, [sp], #16
    ret


//------------------------------------------------------------------------------
// handle time updates, mouse input, and zoom
//------------------------------------------------------------------------------
_update_state:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    mov x29, sp

    // update time
    bl  _window_get_time_seconds_f32
    adrp x19, g_time@PAGE
    add  x19, x19, g_time@PAGEOFF
    str  s0, [x19]

    // update delta-time
    bl  _window_get_delta_seconds_f32
    adrp x19, g_delta_time@PAGE
    add  x19, x19, g_delta_time@PAGEOFF
    str  s0, [x19]

    // update frame counter
    adrp x19, g_frame@PAGE
    add  x19, x19, g_frame@PAGEOFF
    ldr  w20, [x19]
    add  w20, w20, #1
    str  w20, [x19]

    // update mouse uv coordinate
    adrp x0, g_mouse_u@PAGE
    add  x0, x0, g_mouse_u@PAGEOFF
    adrp x1, g_mouse_v@PAGE
    add  x1, x1, g_mouse_v@PAGEOFF
    bl _window_get_mouse_uv_f32

    // zoom controls (mouse buttons): left = zoom in, right = zoom out
    adrp x19, g_zoom@PAGE
    add  x19, x19, g_zoom@PAGEOFF

    // determine zoom direction: left = zoom in (-1), right = zoom out (+1)
    mov  w23, #0                      // dir = 0
    mov  w0, #0
    bl _window_get_mouse_button
    cbz  w0, .L_zoom_check_out
    mov  w23, #-1                     // zoom in
    b    .L_zoom_apply

.L_zoom_check_out:
    mov  w0, #1
    bl _window_get_mouse_button
    cbz  w0, .L_zoom_commit
    mov  w23, #1                      // zoom out

.L_zoom_apply:
    // time-based zoom anchored under the mouse; dir in w23: -1 (in), +1 (out)
    ldr  d20, [x19]                       // old zoom (double)

    // delta time (clamped to 50ms to avoid spikes)
    adrp x0, g_delta_time@PAGE
    ldr  s1, [x0, g_delta_time@PAGEOFF]
    fcvt d1, s1
    adrp x0, g_const_dt_clamp@PAGE
    ldr  d2, [x0, g_const_dt_clamp@PAGEOFF]   // 0.05
    fcmp d1, d2
    b.le .L_dt_clamped
    fmov d1, d2
.L_dt_clamped:
    // factor = 1 + dir * rate * dt  (rate = 1.0 for predictable speed)
    scvtf d3, w23
    adrp x0, g_const_rate@PAGE
    ldr  d4, [x0, g_const_rate@PAGEOFF]       // 1.0
    fmul d3, d3, d4                           // dir*rate
    fmul d3, d3, d1                           // dir*rate*dt
    fmov d5, #1.0
    fadd d3, d3, d5                           // factor = 1.0 + (dir*rate*dt)
    // clamp factor to [0.5, 1.5] (keeps steps sane even if dt spikes)
    adrp x0, g_const_factor_min@PAGE
    ldr  d2, [x0, g_const_factor_min@PAGEOFF] // 0.5
    fcmp d3, d2
    b.hs .L_factor_min_ok
    fmov d3, d2
.L_factor_min_ok:
    adrp x0, g_const_factor_max@PAGE
    ldr  d2, [x0, g_const_factor_max@PAGEOFF] // 1.5
    fcmp d3, d2
    b.le .L_factor_max_ok
    fmov d3, d2
.L_factor_max_ok:
    // new zoom = old * factor
    fmul d19, d20, d3
    // clamp zoom to [1e-6, 8.0]
    adrp x0, g_const_zoom_min@PAGE
    ldr  d2, [x0, g_const_zoom_min@PAGEOFF]
    fcmp d19, d2
    b.hs .L_zoom_min_ok
    fmov d19, d2
.L_zoom_min_ok:
    adrp x0, g_const_zoom_max@PAGE
    ldr  d2, [x0, g_const_zoom_max@PAGEOFF]
    fcmp d19, d2
    b.le .L_zoom_max_ok
    fmov d19, d2
.L_zoom_max_ok:
    // du = (mouse_u - 0.5), dv = (mouse_v - 0.5)
    adrp x0, g_mouse_u@PAGE
    ldr  s6, [x0, g_mouse_u@PAGEOFF]
    adrp x0, g_mouse_v@PAGE
    ldr  s7, [x0, g_mouse_v@PAGEOFF]
    adrp x0, g_const_half@PAGE
    ldr  d5, [x0, g_const_half@PAGEOFF]
    fcvt d6, s6
    fcvt d7, s7
    fsub d6, d6, d5       // du = mouse_u - 0.5
    fsub d7, d7, d5       // dv = mouse_v - 0.5

    // base scale from screen to world (3.0 spans the set at zoom=1)
    adrp x0, g_const_scale@PAGE
    ldr  d8, [x0, g_const_scale@PAGEOFF]      // 3.0

    // old offsets in world space (keep point under cursor stable)
    fmul d9, d6, d8
    fmul d9, d9, d20                          // * old zoom
    fmul d10, d7, d8
    fmul d10, d10, d20

    // load current center (double)
    adrp x0, g_center_x@PAGE
    ldr  d11, [x0, g_center_x@PAGEOFF]
    adrp x0, g_center_y@PAGE
    ldr  d12, [x0, g_center_y@PAGEOFF]

    // mouse_world = center + old_offset
    fadd d13, d11, d9
    fadd d14, d12, d10

    // new offsets with updated zoom
    fmul d15, d6, d8
    fmul d15, d15, d19
    fmul d16, d7, d8
    fmul d16, d16, d19

    // new center to keep mouse_world fixed
    fsub d17, d13, d15
    fsub d18, d14, d16

    // clamp center to a safe box around the set: x in [-2.5, 1.5], y in [-2.0, 2.0]
    adrp x0, g_const_cx_min@PAGE
    ldr  d8, [x0, g_const_cx_min@PAGEOFF]
    fcmp d17, d8
    b.ge .L_cx_min_ok
    fmov d17, d8
.L_cx_min_ok:
    adrp x0, g_const_cx_max@PAGE
    ldr  d8, [x0, g_const_cx_max@PAGEOFF]
    fcmp d17, d8
    b.le .L_cx_max_ok
    fmov d17, d8
.L_cx_max_ok:
    adrp x0, g_const_cy_min@PAGE
    ldr  d8, [x0, g_const_cy_min@PAGEOFF]
    fcmp d18, d8
    b.ge .L_cy_min_ok
    fmov d18, d8
.L_cy_min_ok:
    adrp x0, g_const_cy_max@PAGE
    ldr  d8, [x0, g_const_cy_max@PAGEOFF]
    fcmp d18, d8
    b.le .L_cy_max_ok
    fmov d18, d8
.L_cy_max_ok:
    // store zoom and center (double state)
    str  d19, [x19]
    adrp x0, g_center_x@PAGE
    str  d17, [x0, g_center_x@PAGEOFF]
    adrp x0, g_center_y@PAGE
    str  d18, [x0, g_center_y@PAGEOFF]

.L_zoom_commit:

    // snapshot center/zoom for this frame (avoid mid-render changes)
    adrp x0, g_center_x@PAGE
    ldr  d0, [x0, g_center_x@PAGEOFF]
    adrp x1, g_center_x_frame@PAGE
    str  d0, [x1, g_center_x_frame@PAGEOFF]

    adrp x0, g_center_y@PAGE
    ldr  d0, [x0, g_center_y@PAGEOFF]
    adrp x1, g_center_y_frame@PAGE
    str  d0, [x1, g_center_y_frame@PAGEOFF]

    adrp x0, g_zoom@PAGE
    ldr  d0, [x0, g_zoom@PAGEOFF]
    adrp x1, g_zoom_frame@PAGE
    str  d0, [x1, g_zoom_frame@PAGEOFF]

    bl   _update_max_iter

    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret


//------------------------------------------------------------------------------
// select active framebuffer and dispatch render job
//------------------------------------------------------------------------------
_render_frame:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    
    // select back buffer based on g_fb_index
    bl _get_current_fb_ptr
    
    // arguments for renderer: x0=fb, w1=w, w2=h, w3=stride
    mov  w1, #SCREEN_WIDTH
    mov  w2, #SCREEN_HEIGHT
    mov  w3, #SCREEN_ROW_STRIDE
    bl   _mandelbrot_render

    ldp x29, x30, [sp], #16
    ret


//------------------------------------------------------------------------------
// present the current buffer and swap to next
//------------------------------------------------------------------------------
_present_frame:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // present the buffer we just rendered
    bl _get_current_fb_ptr
    mov x1, #SCREEN_ROW_STRIDE
    bl _window_present

    // g_fb_index = (g_fb_index + 1) % 3
    adrp x9, g_fb_index@PAGE
    ldr  w10, [x9, g_fb_index@PAGEOFF]
    add  w10, w10, #1
    cmp  w10, #3
    csel w10, w10, wzr, lt
    str  w10, [x9, g_fb_index@PAGEOFF]

    ldp x29, x30, [sp], #16
    ret


//------------------------------------------------------------------------------
// returns x0 = pointer to current framebuffer (based on g_fb_index)
//------------------------------------------------------------------------------
_get_current_fb_ptr:
    adrp x9, g_fb_index@PAGE
    ldr  w10, [x9, g_fb_index@PAGEOFF]
    adrp x0, g_framebuffer_a@PAGE
    add  x0, x0, g_framebuffer_a@PAGEOFF
    adrp x1, g_framebuffer_b@PAGE
    add  x1, x1, g_framebuffer_b@PAGEOFF
    adrp x2, g_framebuffer_c@PAGE
    add  x2, x2, g_framebuffer_c@PAGEOFF
    cmp  w10, #1
    csel x0, x0, x1, eq      // w10 == 1 -> buffer_b
    cmp  w10, #2
    csel x0, x0, x2, eq      // w10 == 2 -> buffer_c
    ret


//------------------------------------------------------------------------------
// compute max_iter from g_zoom_frame once per frame
//------------------------------------------------------------------------------
.globl _update_max_iter
_update_max_iter:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, g_zoom_frame@PAGE
    ldr  d0, [x0, g_zoom_frame@PAGEOFF]
    bl   _log
    adrp x0, g_const_ln2@PAGE
    ldr  d1, [x0, g_const_ln2@PAGEOFF]
    fdiv d0, d0, d1
    fneg d0, d0                       // log2(1/zoom)
    fmov d1, #1.0
    fadd d0, d0, d1                   // 1 + log2(1/zoom)
    adrp x0, g_const_iter_quality@PAGE
    ldr  d1, [x0, g_const_iter_quality@PAGEOFF]
    fmul d0, d0, d1                   // quality * (1 + log2(1/zoom))
    adrp x0, g_const_iter_min@PAGE
    ldr  d1, [x0, g_const_iter_min@PAGEOFF]
    fcmp d0, d1
    b.ge .L_iter_min_ok
    fmov d0, d1
.L_iter_min_ok:
    adrp x0, g_const_iter_max@PAGE
    ldr  d1, [x0, g_const_iter_max@PAGEOFF]
    fcmp d0, d1
    b.le .L_iter_max_ok
    fmov d0, d1
.L_iter_max_ok:
    fcvtzs w0, d0
    adrp x1, g_max_iter_frame@PAGE
    str  w0, [x1, g_max_iter_frame@PAGEOFF]
    ldp x29, x30, [sp], #16
    ret



//------------------------------------------------------------------------------

.section __DATA,__data

.p2align 6
g_frame_uniforms:
.globl g_time
g_time:         .float 0.0
.globl g_delta_time
g_delta_time:   .float 0.0
.globl g_mouse_u
g_mouse_u:      .float  0.0    // mouse position in UV coordinates
.globl g_mouse_v
g_mouse_v:      .float  0.0    // mouse position in UV coordinates
.globl g_frame
g_frame:        .word  0
.p2align 3
.globl g_center_x
g_center_x:    .double -0.5
.globl g_center_y
g_center_y:    .double 0.0
.globl g_zoom
g_zoom:        .double 1.0
// per-frame snapshot for renderer
.p2align 3
.globl g_center_x_frame
g_center_x_frame: .double -0.5
.globl g_center_y_frame
g_center_y_frame: .double 0.0
.globl g_zoom_frame
g_zoom_frame:     .double 1.0
g_zoom_in_factor:  .float 0.99
g_zoom_out_factor: .float 1.01
.globl g_thread_count
g_thread_count: .word 10

.globl g_max_iter_frame
g_max_iter_frame: .word 0

// double-precision constants for zoom math
.p2align 3
g_const_dt_clamp:    .double 0.05
g_const_rate:        .double 0.3
g_const_factor_min:  .double 0.5
g_const_factor_max:  .double 1.5
g_const_zoom_min:    .double 1.0e-14
g_const_zoom_max:    .double 8.0
g_const_half:        .double 0.5
g_const_scale:       .double 3.0
g_const_cx_min:      .double -4.0
g_const_cx_max:      .double  4.0
g_const_cy_min:      .double -4.0
g_const_cy_max:      .double  4.0
g_const_ln2:         .double 0.6931471805599453
g_const_iter_quality: .double 8.0   // single quality knob: 10=fast/colorful, 50=balanced, 100=detailed
g_const_iter_min:    .double 40.0
g_const_iter_max:    .double 2000.0

.section __DATA,__bss

.p2align 6 // align in 64 bytes chunks
g_framebuffer_a: .space SCREEN_BUFF_SIZE
g_framebuffer_b: .space SCREEN_BUFF_SIZE
g_framebuffer_c: .space SCREEN_BUFF_SIZE

.p2align 2
g_fb_index: .word 0
