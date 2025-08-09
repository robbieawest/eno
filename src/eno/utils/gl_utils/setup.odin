package opengl

import gl "vendor:OpenGL"

import dbg "../../debug"


// Setting up opengl

opengl_setup :: proc() {
    opengl_debug_setup()
    // enable_gl_depth_test()
}

opengl_debug_setup :: proc() {
    if dbg.DEBUG_MODE == .DEBUG {
        gl.Enable(gl.DEBUG_OUTPUT)
        gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
    }
    gl.DebugMessageCallback(dbg.GL_DEBUG_CALLBACK, nil)  // Enable even if debug mode off, does nothing if off, allows debug to be turned on mid runtime
}

enable_gl_depth_test :: proc() {
    gl.Enable(gl.DEPTH_TEST)
}

frame_setup :: proc() {
    gl_clear()
}

// Use gl_add_clear_attributes and gl_remove_clear_attributes to modify
@(private)
GL_CLEAR_MASK : u32 = gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT

gl_add_clear_attributes :: proc(attributes: ..u32) {
    for attribute in attributes do GL_CLEAR_MASK |= attribute
}

gl_remove_clear_attributes :: proc(attributes: ..u32) {
    for attribute in attributes do GL_CLEAR_MASK &~= attribute
}

gl_clear :: proc() {
    gl.Clear(GL_CLEAR_MASK)
}
