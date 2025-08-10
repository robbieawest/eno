package opengl

import gl "vendor:OpenGL"

import dbg "../../debug"


opengl_debug_setup :: proc() {
    if dbg.DEBUG_MODE == .DEBUG {
        gl.Enable(gl.DEBUG_OUTPUT)
        gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
    }
    gl.DebugMessageCallback(dbg.GL_DEBUG_CALLBACK, nil)  // Enable even if debug mode off, does nothing if off, allows debug to be turned on mid runtime
}