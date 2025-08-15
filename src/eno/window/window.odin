package window

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"

import glutils "../utils/gl_utils"
import dbg "../debug"

import "core:log"
import "core:c"
import "core:strings"

WINDOW_WIDTH: i32 = 1280
WINDOW_HEIGHT: i32 = 720 

WindowTarget :: ^SDL.Window

initialize_window :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (win_ret: WindowTarget) {
    window: ^SDL.Window
    c_window_tag := strings.clone_to_cstring(window_tag)

    if len(extra_params) != 0 {
        if len(extra_params) != 2 {
            dbg.log(.ERROR, "Not enough params given to initialize SDL window")
            return
        }

        window = SDL.CreateWindow(c_window_tag, extra_params[0], extra_params[1], width, height, SDL.WINDOW_OPENGL)
    } else {
        window = SDL.CreateWindow(c_window_tag, SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, width, height, SDL.WINDOW_OPENGL)
    }

    // SDL.CreateRenderer(window, -1, SDL.RENDERER_ACCELERATED)

	if window == nil {
        dbg.log(.ERROR, "Could not initialize SDL window")
        return
	}

    WINDOW_WIDTH = width
    WINDOW_HEIGHT = height

    sdl_setup_gl_versioning()
    gl_context := SDL.GL_CreateContext(window)
    SDL.GL_MakeCurrent(window, gl_context)
    gl.load_up_to(4, 3, SDL.gl_set_proc_address)

    if (SDL.GL_SetSwapInterval(1) < 0) {
        dbg.log(.ERROR, "Could not set VSYNC to on")
        return
    }

    sdl_setup_gl_multisamples()
    glutils.opengl_debug_setup()

    dbg.init_debug()
    dbg.log(.INFO, "Initialized SDL window")

    win_ret = window
    return
}

sdl_setup_gl_versioning :: proc() {
    dbg.log(.INFO, "Setting SDL GL versioning")
    _attr_ret: i32
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))
    // _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_FLAGS, i32(SDL.GLcontextFlag.DEBUG_FLAG))
    if _attr_ret != 0 do dbg.log(.ERROR, "Could not set certain SDL parameters for OpenGL")
}

sdl_setup_gl_multisamples :: proc() {
    _attr_ret: i32
    _attr_ret |= SDL.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
    _attr_ret |= SDL.GL_SetAttribute(.MULTISAMPLESAMPLES, 8)
    if _attr_ret != 0 do dbg.log(.ERROR, "Could not set multisample SDL parameters for OpenGL")
}


destroy_window :: proc(window_target: WindowTarget) {
    dbg.log(.INFO, "Destroying SDL window")
    SDL.DestroyWindow(window_target)
}


swap_window_bufs :: proc(target: WindowTarget) -> (ok: bool) {
    SDL.GL_SwapWindow(target)
    return true
}


WindowResolution :: struct {
    w: i32, h: i32
}

get_window_resolution :: proc(window_target: WindowTarget) -> (res: WindowResolution) {
    SDL.GetWindowSize(window_target, &res.w, &res.h)
    return
}


// Aspect ratio

get_aspect_ratio :: proc(window_target: WindowTarget) -> (ratio: f32, ok: bool) #optional_ok {
    res := get_window_resolution(window_target);
    return get_aspect_ratio_from_resolution(res), true;
}

get_aspect_ratio_from_resolution :: proc(res: WindowResolution) -> (ratio: f32) {
    return f32(res.w) / f32(res.h)
}


// Mouse

set_mouse_relative_mode :: proc(flag: bool) {
    SDL.SetRelativeMouseMode(SDL.bool(flag))
}

set_mouse_raw_input :: proc(flag: bool) {
    if flag {
        is_relative := SDL.GetRelativeMouseMode()
        if is_relative do SDL.SetRelativeMouseMode(false)
        SDL.SetHint(SDL.HINT_MOUSE_RELATIVE_MODE_WARP, "0")
        if is_relative do SDL.SetRelativeMouseMode(true)

    } else{
        SDL.SetHint(SDL.HINT_MOUSE_RELATIVE_MODE_WARP, "1")
    }
}


set_fullscreen :: proc(window_target: WindowTarget) -> (ok: bool) {

    sdl_err := SDL.SetWindowFullscreen(window_target, SDL.WINDOW_FULLSCREEN)
    if sdl_err != 0 {
        last_sdl_err: cstring = SDL.GetError()
        dbg.log(.ERROR, "Error while enabling fullscreen, sdl error: %s", last_sdl_err)
        return
    }

    ok = true
    return
}