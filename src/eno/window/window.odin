package window

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"
import "vendor:glfw"

import gpu "../gpu"
import dbg "../debug"

import "core:log"
import "core:strings"
import "base:runtime"
import "core:fmt"

// This file defines how eno interacts with the windower (SDL implemented currently)

Windower :: enum { SDL, GLFW }
CURRENT_WINDOWER: Windower = .SDL


GLFW_ERROR_CALLBACK :: proc "c" (error: i32, description: cstring) {
    context = runtime.default_context()
    context.logger = log.create_console_logger()
    fmt.print("\nglfw error\n")
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
init_win_ :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (WindowTarget, bool)
initialize_window: init_win_ = SDL_init_window


@(private)
SDL_init_window :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (ret_win: WindowTarget, ok: bool) {
    dbg.init_debug_stack()
    dbg.debug_point( dbg.LogInfo{ msg = "INIT DEBUG STACK", level = .INFO} )

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
    case .VULKAN: gpu.vulkan_not_supported()
    case. OPENGL:
        gl_context := SDL.GL_CreateContext(window)
        SDL.GL_MakeCurrent(window, gl_context)
        gl.load_up_to(4, 3, SDL.gl_set_proc_address) // Loads odin gl procedure bindings?

        _attr_ret: i32
        _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
        _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
        _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))
        _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_FLAGS, i32(SDL.GLcontextFlag.DEBUG_FLAG))
        if _attr_ret != 0 do log.errorf("Could not set certain SDL parameters for OpenGL")

        gl.Enable(gl.DEBUG_OUTPUT)
        gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
        gl.DebugMessageCallback(dbg.GL_DEBUG_CALLBACK, nil)
    }

    return window, true
}

GLFW_init_window :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (ret_win: WindowTarget, ok: bool) {
    dbg.init_debug_stack()
    dbg.debug_point( dbg.LogInfo{ msg = "INIT DEBUG STACK", level = .INFO} )

    window_tag_cstr := strings.clone_to_cstring(window_tag)
    window: glfw.WindowHandle = glfw.CreateWindow(width, height, window_tag_cstr, nil, nil)
    if window == nil {
        log.errorf("Failed to initialize GLFW window")
        return window, ok
    }

    glfw.MakeContextCurrent(window)
    glfw.SetErrorCallback(GLFW_ERROR_CALLBACK)
	glfw.WindowHint(glfw.RESIZABLE, 1)

    switch (gpu.RENDER_API) {
    case .VULKAN: gpu.vulkan_not_supported()
    case .OPENGL:
        glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR,4) 
        glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR,6)
        glfw.WindowHint(glfw.OPENGL_PROFILE,glfw.OPENGL_CORE_PROFILE)
        gl.DebugMessageCallback(dbg.GL_DEBUG_CALLBACK, nil)
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
GLFW_destroy_window :: proc(target: WindowTarget) {
    glfw.DestroyWindow(target.(glfw.WindowHandle))
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
