package window

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"

import gpu "../gpu"

import "core:log"
import "core:strings"

// This file defines how eno interacts with the windower (SDL implemented currently)

Windower :: enum { SDL, GLFW }
CURRENT_WINDOWER: Windower = .SDL


use_windower :: proc(windower: Windower) -> (ok: bool) {
    CURRENT_WINDOWER = windower
    switch (CURRENT_WINDOWER) {
    case .SDL:
        initialize_window = SDL_init_window
        destroy_window = SDL_destroy_window
        swap_window_bufs = SDL_swap_window_bufs
    case .GLFW:
        log.errorf("GLFW not yet supported")
        return ok
    }
    return true
}


WindowTarget :: union {
    ^SDL.Window
}


@(private)
init_win_ :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (WindowTarget, bool)
initialize_window: init_win_ = SDL_init_window


@(private)
SDL_init_window :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (ret_win: WindowTarget, ok: bool) {
    window: ^SDL.Window
    c_window_tag := strings.clone_to_cstring(window_tag)

    render_api_winflags := gpu.RENDER_API == .OPENGL ? SDL.WINDOW_OPENGL : SDL.WINDOW_VULKAN
    if len(extra_params) != 0 {
        if len(extra_params) != 2 {
            log.errorf("Not enough extra params given to SDL window initialization")
            return ret_win, ok
        }

        window = SDL.CreateWindow(c_window_tag, extra_params[0], extra_params[1], width, height, render_api_winflags)
    } else {
        window = SDL.CreateWindow(c_window_tag, SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, width, height, render_api_winflags)
    }

	if window == nil {
        log.errorf("Could not initialize SDL window")
		return window, ok
	}
	
    // Extra steps for render apis
    switch (gpu.RENDER_API) {
    case. OPENGL:
        gl_context := SDL.GL_CreateContext(window)
        SDL.GL_MakeCurrent(window, gl_context)
        gl.load_up_to(4, 3, SDL.gl_set_proc_address)
    case .VULKAN:
        gpu.vulkan_not_supported()
    }

    return window, true
}


destroy_window_ :: proc(target: WindowTarget)
destroy_window: destroy_window_  = SDL_destroy_window


@(private)
SDL_destroy_window :: proc(target: WindowTarget) {
    SDL.DestroyWindow(target.(^SDL.Window))
}


@(private)
swap_win_ :: proc(target: WindowTarget) -> bool
swap_window_bufs: swap_win_ = SDL_swap_window_bufs


@(private)
SDL_swap_window_bufs :: proc(target: WindowTarget) -> (ok: bool) {
    switch (gpu.RENDER_API) {
    case .OPENGL:
        sdl_window, ok := parse_sdl_window_target(target); if !ok do return ok
        SDL.GL_SwapWindow(sdl_window)
    case .VULKAN:
        gpu.vulkan_not_supported()
        return ok
    }
    return true
}


@(private)
parse_sdl_window_target :: proc(window_target: WindowTarget) -> (result: ^SDL.Window, ok: bool) {
    result, ok = window_target.(^SDL.Window)
    if !ok {
        log.errorf("How can windower be SDL and yet target is not??")
        return result, ok
    }
    return result, true
}
