package window

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"
import "vendor:glfw"

import gpu "../gpu"
import dbg "../debug"

import "core:log"
import "core:c"
import "core:strings"
import "base:runtime"
import "core:fmt"

// This file defines how eno interacts with the windower (SDL implemented currently)

Windower :: enum { SDL, GLFW }
CURRENT_WINDOWER: Windower = .SDL

WINDOW_WIDTH: i32 = 1280
WINDOW_HEIGHT: i32 = 720 


GLFW_ERROR_CALLBACK :: proc "c" (error: i32, description: cstring) {
    context = runtime.default_context()
    context.logger = log.create_console_logger()
    log.errorf("GLFW error raised : %d : %s", error, description)
}


use_windower :: proc(windower: Windower) -> (ok: bool) {
    CURRENT_WINDOWER = windower
    switch (CURRENT_WINDOWER) {
    case .SDL:
        initialize_window = SDL_init_window
        destroy_window = SDL_destroy_window
        swap_window_bufs = SDL_swap_window_bufs
    case .GLFW:
        initialize_window = GLFW_init_window
        destroy_window = GLFW_destroy_window
        swap_window_bufs = GLFW_swap_window_bufs
        return ok
    }
    return true
}


WindowTarget :: union {
    ^SDL.Window,
    glfw.WindowHandle
}


@(private)
init_win_ :: #type proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (WindowTarget)
initialize_window: init_win_ = SDL_init_window


@(private)
SDL_init_window :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (win_ret: WindowTarget) {
    dbg.init_debug_stack()
    dbg.debug_point(dbg.LogLevel.INFO, "Initializing SDL window")

    window: ^SDL.Window
    c_window_tag := strings.clone_to_cstring(window_tag)
    
    render_api_winflags := gpu.RENDER_API == .OPENGL ? SDL.WINDOW_OPENGL : SDL.WINDOW_VULKAN
    if len(extra_params) != 0 {
        if len(extra_params) != 2 {
            dbg.debug_point(dbg.LogLevel.ERROR, "Not enough params given to initialize SDL window")
            return
        }

        window = SDL.CreateWindow(c_window_tag, extra_params[0], extra_params[1], width, height, render_api_winflags)
    } else {
        window = SDL.CreateWindow(c_window_tag, SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, width, height, render_api_winflags)
    }

	if window == nil {
        dbg.debug_point(dbg.LogLevel.ERROR, "Could not initialize SDL window")
        return
	}

    WINDOW_WIDTH = width
    WINDOW_HEIGHT = height
	
    // Extra steps for render apis
    switch (gpu.RENDER_API) {
    case .VULKAN: gpu.vulkan_not_supported()
    case. OPENGL:
        gl_context := SDL.GL_CreateContext(window)
        SDL.GL_MakeCurrent(window, gl_context)
        gl.load_up_to(4, 3, SDL.gl_set_proc_address)

        sdl_setup_gl_versioning()
        gpu.opengl_setup()
    }

    win_ret = window
    return
}

sdl_setup_gl_versioning :: proc() {
    _attr_ret: i32
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_FLAGS, i32(SDL.GLcontextFlag.DEBUG_FLAG))
    if _attr_ret != 0 do log.errorf("Could not set certain SDL parameters for OpenGL")
}


GLFW_init_window :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (win_ret: WindowTarget) {
    dbg.init_debug_stack()
    dbg.debug_point(dbg.LogLevel.INFO, "Initializing GLFW window")

    window_tag_cstr := strings.clone_to_cstring(window_tag)
    window: glfw.WindowHandle = glfw.CreateWindow(width, height, window_tag_cstr, nil, nil)
    if window == nil {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to initialize GLFW window")
        return
    }

    glfw.MakeContextCurrent(window)
    glfw.SetErrorCallback(GLFW_ERROR_CALLBACK)
	glfw.WindowHint(glfw.RESIZABLE, 1)

    switch (gpu.RENDER_API) {
    case .VULKAN: gpu.vulkan_not_supported()
    case .OPENGL:
        glfw_setup_gl_versioning()
        gpu.opengl_setup()
    }

    win_ret = window
    return
}


glfw_setup_gl_versioning :: proc() {
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR,4)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR,6)
    glfw.WindowHint(glfw.OPENGL_PROFILE,glfw.OPENGL_CORE_PROFILE)
}

destroy_window_ :: proc(target: WindowTarget)
destroy_window: destroy_window_  = SDL_destroy_window


@(private)
SDL_destroy_window :: proc(target: WindowTarget) {
    dbg.debug_point(dbg.LogLevel.INFO, "Destroying SDL window")
    SDL.DestroyWindow(target.(^SDL.Window))
}

@(private)
GLFW_destroy_window :: proc(target: WindowTarget) {
    dbg.debug_point(dbg.LogLevel.INFO, "Destroying GLFW window")
    glfw.DestroyWindow(target.(glfw.WindowHandle))
}


@(private)
swap_win_ :: proc(target: WindowTarget) -> bool
swap_window_bufs: swap_win_ = SDL_swap_window_bufs


@(private)
SDL_swap_window_bufs :: proc(target: WindowTarget) -> (ok: bool) {
    switch (gpu.RENDER_API) {
    case .OPENGL:
       // gpu.gl_clear()
        sdl_window, ok := parse_sdl_window_target(target); if !ok do return ok
        SDL.GL_SwapWindow(sdl_window)
    case .VULKAN:
        gpu.vulkan_not_supported()
        return ok
    }
    return true
}

@(private)
GLFW_swap_window_bufs :: proc(target: WindowTarget) -> (ok: bool) {
    ok = true
    glfw.SwapBuffers(target.(glfw.WindowHandle))
    return ok
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


WindowResolution :: struct {
    w: u32, h: u32
}

get_window_resolution :: proc(window_target: WindowTarget) -> (res: WindowResolution, ok: bool) #optional_ok {
    sdl_win: ^SDL.Window
    sdl_win, ok = window_target.(^SDL.Window); if !ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "Not supported")
        return
    }

    win_flags: SDL.WindowFlags = transmute(SDL.WindowFlags) SDL.GetWindowFlags(sdl_win)
    if .FULLSCREEN in win_flags {
        x, y: c.int
        sdl_err := SDL.GetRendererOutputSize(SDL.GetRenderer(sdl_win), &x, &y)
        if sdl_err != 0 {
            dbg.debug_point(dbg.LogLevel.ERROR, "Failed to get fullscreen resolution, SDL error code: %d", sdl_err)
            return
        }
        res = WindowResolution { u32(x), u32(y) }
    }
    else {
        display_mode: SDL.DisplayMode
        sdl_err := SDL.GetDesktopDisplayMode(0, &display_mode)
        if sdl_err != 0 {
            dbg.debug_point(dbg.LogLevel.ERROR, "Failed to get window resolution, SDL error code: %d", sdl_err)
            return
        }

        res = WindowResolution { u32(display_mode.w), u32(display_mode.h) }
    }

    ok = true
    return
}


get_aspect_ratio :: proc(window_target: WindowTarget) -> (ratio: f32, ok: bool) #optional_ok {
    res: WindowResolution; res, ok = get_window_resolution(window_target); if !ok do return
    return get_aspect_ratio_from_resolution(res), true;
}

get_aspect_ratio_from_resolution :: proc(res: WindowResolution) -> (ratio: f32) {
    return f32(res.w) / f32(res.h)
}