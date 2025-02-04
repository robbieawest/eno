package gpu

import gl "vendor:OpenGL"

import "../model"
import dbg "../debug"

import "core:log"



GraphicsAPI :: enum { OPENGL, VULKAN } //Making it easy for the future - Is it really? Not doing vulkan any time soon no need to keep doing this
RENDER_API: GraphicsAPI = GraphicsAPI.OPENGL



GlComponentStates :: enum {
    VAO_TRANSFERRED,
    VBO_TRANSFERRED,
    EBO_TRANSFERRED,
}
GlComponentState :: bit_set[GlComponentStates]

gl_component_is_drawable :: proc(component: model.GLComponent) -> GlComponentState {
    return (u32(!component.vao.transferred)) | (u32(!component.vbo.transferred) << 1) | (u32(!component.ebo.transferred) << 2)
}

// todo look at shaders for this
release_mesh :: proc(mesh: model.Mesh) {
    delete(mesh.vertex_data)
    delete(mesh.index_data)
    gl.DeleteVertexArrays(1, &mesh.gl_component.vao.id)
    gl.DeleteBuffers(1, &mesh.gl_component.vbo.id)
    gl.DeleteBuffers(1, &mesh.gl_component.ebo.id)
}

release_model :: proc(model: model.Model) {
    for mesh in model.meshes do release_mesh(model)
}



/* Main output returned via side effects */
express_draw_properties :: proc(draw_properties: ^DrawProperties) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing draw properties")

    gl_express_mesh_with_indices(draw_properties) or_return
    log.infof("gpu component after: %#v", draw_properties.gpu_component)

    return express_shader_given_gpu_component(&draw_properties.gpu_component)
}

@(private)
express_shader_given_gpu_component :: proc(gpu_comp: ^GPUComponent) -> (ok: bool){
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing shader given gpu components")
    gl_comp: ^gl_GPUComponent
    switch &comp in gpu_comp {
    case gl_GPUComponent:
        gl_comp = &comp
    case vl_GPUComponent:
        vulkan_not_supported()
        ok = false
        return
    }

    if !gl_comp.program.expressed do return express_shader(&gl_comp.program)

    ok = true
    return
}


// Procedures to express mesh structures on the GPU
gl_express_mesh_with_indices :: proc(draw_properties: ^DrawProperties) -> (ok: bool) {
    if RENDER_API == .VULKAN {
        vulkan_not_supported()
        return
    }

    gpu_component := draw_properties.gpu_component.(gl_GPUComponent)

    gl.GenVertexArrays(1, &gpu_component.vao)
    gl.BindVertexArray(gpu_component.vao)

    if !gpu_component.expressed_vert {
        // Express ebo
        gl_create_and_express_vbo(&gpu_component.vbo, &draw_properties.mesh) or_return
        gpu_component.expressed_vert = true
    }

    if !gpu_component.expressed_ind {
        // Express ebo
         gl_create_and_express_ebo(&gpu_component.ebo, &draw_properties.indices)
         gpu_component.expressed_ind = true
    }

    draw_properties.gpu_component = gpu_component
    ok = true
    return
}


/*
    Assumes not expressed
    Assumes bound vao
*/
@(private)
gl_create_and_express_vbo :: proc(vbo: ^u32, data: ^model.Mesh) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing gl mesh vertices")
    if len(data.vertex_data) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "No vertices given to express");
        return
    }

    gl.GenBuffers(1, vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo^)

    total_byte_stride: u32 = 0; for attribute_layout in data.layout do total_byte_stride += attribute_layout.byte_stride

   // log.infof("vbo: %d", gl_component.vbo)
   // log.infof("stride: %d", stride)
   // log.infof("mesh: %#v, layout: %#v, s: %d", len(mesh.vertex_data), mesh.layout, len(mesh.vertex_data))
    gl.BufferData(gl.ARRAY_BUFFER, len(data.vertex_data) * size_of(f32), raw_data(data.vertex_data), gl.STATIC_DRAW)

    offset, current_ind: u32 = 0, 0
    for attribute_info in data.layout {
        gl.VertexAttribPointer(current_ind, i32(attribute_info.float_stride), gl.FLOAT, gl.FALSE, i32(total_byte_stride), uintptr(offset) * size_of(f32))
        gl.EnableVertexAttribArray(current_ind)

        offset += attribute_info.float_stride
        current_ind += 1
    }

    ok = true
    return
}


/*
    Assumes not expressed
    Assumes bound vao
*/
@(private)
gl_create_and_express_ebo :: proc(ebo: ^u32, data: ^model.IndexData) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing gl mesh indices")
    if len(data.raw_data) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Cannot express 0 indices")
        return
    }

    gl.GenBuffers(1, ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo^)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(data.raw_data) * size_of(u32), raw_data(data.raw_data), gl.STATIC_DRAW)

    ok = true
    return
}

//


draw_elements_ :: #type proc(draw_properties: ^DrawProperties)
draw_elements: draw_elements_ = gl_draw_elements

gl_draw_elements :: proc(draw_properties: ^DrawProperties) {
    // todo add checks for expressedness of components
    comp := draw_properties.gpu_component.(gl_GPUComponent)
    gl.BindVertexArray(comp.vao)
    gl.UseProgram(u32(comp.program.id.(i32)))
    gl.DrawElements(gl.TRIANGLES, i32(len(draw_properties.indices.raw_data)), gl.UNSIGNED_INT, nil)
}


vulkan_not_supported :: proc(loc := #caller_location) { dbg.debug_point(dbg.LogLevel.ERROR, "Vulkan not supported", loc = loc) }


// Setting up opengl

opengl_setup :: proc() {
    opengl_debug_setup()
    enable_gl_depth_test()
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
    if RENDER_API == .VULKAN {
        vulkan_not_supported()
        return
    }
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