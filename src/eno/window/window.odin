package window

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"

import glutils "../utils/gl_utils"
import dbg "../debug"

import "core:log"
import "core:strings"

WINDOW_WIDTH: i32 = 1280
WINDOW_HEIGHT: i32 = 720 

WindowTarget :: ^SDL.Window

initialize_window :: proc(width, height: i32, window_tag: string, extra_params: ..i32) -> (win_ret: WindowTarget, ok: bool) {
    window: ^SDL.Window
    c_window_tag := strings.clone_to_cstring(window_tag)

    if len(extra_params) != 0 {
        if len(extra_params) != 2 {
            log.errorf("Not enough params given to initialize SDL window")
            return
        }

        window = SDL.CreateWindow(c_window_tag, extra_params[0], extra_params[1], width, height, SDL.WINDOW_OPENGL)
    } else {
        window = SDL.CreateWindow(c_window_tag, SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, width, height, SDL.WINDOW_OPENGL)
    }

	if window == nil {
        log.errorf("Could not initialize SDL window")
        return
	}

    WINDOW_WIDTH = width
    WINDOW_HEIGHT = height

    sdl_setup_gl_versioning()
    sdl_setup_gl_multisamples()

    gl_context := SDL.GL_CreateContext(window)
    if gl_context == nil {
        log.errorf("Failed to create gl context")
        log.errorf("SDL Err: '%v'", SDL.GetErrorString())
        return
    }
    if SDL.GL_MakeCurrent(window, gl_context) != 0 {
        log.errorf("Failed to make gl context current")
        log.errorf("SDL Err: '%v'", SDL.GetErrorString())
        return
    }

    gl.load_up_to(4, 3, SDL.gl_set_proc_address)
    glutils.opengl_debug_setup()

    dbg.init_debug()

    if (SDL.GL_SetSwapInterval(1) < 0) {
        dbg.log(.ERROR, "Could not set VSYNC to on")
        return
    }

    dbg.log(.INFO, "Initialized SDL window")

    win_ret = window
    ok = true
    return
}

sdl_setup_gl_versioning :: proc() {
    log.infof("Setting SDL GL versioning")
    _attr_ret: i32
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_FLAGS, i32(SDL.GLcontextFlag.DEBUG_FLAG))
    if _attr_ret != 0 do log.errorf("Could not set certain SDL parameters for OpenGL")
}

sdl_setup_gl_multisamples :: proc() {
    _attr_ret: i32
    _attr_ret |= SDL.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
    _attr_ret |= SDL.GL_SetAttribute(.MULTISAMPLESAMPLES, 8)
    if _attr_ret != 0 do  log.errorf("Could not set multisample SDL parameters for OpenGL")
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