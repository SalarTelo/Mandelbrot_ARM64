//
// Created by Salar Loran Telo on 2026-01-08.
//

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Creates a window with the specified dimensions.
 * Returns 0 on success, -1 on failure.
 * Must be called before any other window functions.
 */
int window_create(int width, int height);

/**
 * Polls and processes window events (key presses, mouse input, etc).
 * Should be called regularly in the main loop.
 */
void window_poll_events(void);

/**
 * Returns non-zero if the window should close, 0 otherwise.
 * Check this in your main loop to determine when to exit.
 */
int window_should_close(void);

/**
 * Presents RGBA pixel data to the window.
 * pixel_data: pointer to RGBA pixel buffer (4 bytes per pixel)
 * stride: bytes per row (should be width * 4 for tightly packed data)
 */
void window_present(const void* pixel_data, int stride);

/**
 * Destroys the window and releases all resources.
 * Safe to call even if window_create failed.
 */
void window_destroy(void);

/**
 * Gets elapsed time in nanoseconds since window_create was called.
 */
uint64_t window_get_time_ns(void);

/**
 * Gets delta time in nanoseconds since last call to window_poll_events.
 * First call after create returns 0.
 */
uint64_t window_get_delta_ns(void);

/**
 * Gets elapsed time in seconds since window_create was called.
 */
double window_get_time_seconds(void);

/**
 * Gets elapsed time in seconds since window_create was called (float).
 */
float window_get_time_seconds_f32(void);

/**
 * Gets delta time in seconds since last call to window_poll_events (float).
 */
float window_get_delta_seconds_f32(void);

/**
 * Writes normalized mouse coordinates in [0,1] to out_u/out_v (if non-NULL).
 * Values are clamped to the window bounds and are expressed in backing pixels.
 */
void window_get_mouse_uv_f32(float *out_u, float *out_v);

/**
 * Returns mouse button state (0: left, 1: right, 2: middle).
 * Returns 1 if down, 0 if up.
 */
int window_get_mouse_button(int button);

/**
 * Writes the current mouse position into out_x and out_y (if non-NULL).
 */
void window_get_mouse_position(double *out_x, double *out_y);

#ifdef __cplusplus
}
#endif
