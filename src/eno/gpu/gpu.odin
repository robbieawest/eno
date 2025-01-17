package gpu

import gl "vendor:OpenGL"

import "../model"
import dbg "../debug"

import "core:testing"
import "core:log"
import "core:strings"
import "core:fmt"
import "base:runtime"
import glm "core:math/linalg/glsl"


GraphicsAPI :: enum { OPENGL, VULKAN } //Making it easy for the future - Is it really? Not doing vulkan any time soon no need to keep doing this
RENDER_API: GraphicsAPI = GraphicsAPI.OPENGL


// Defined way to store VAO, VBO, EBO in the entity component system

GPUComponent :: union #no_nil {
    gl_GPUComponent,
    vl_GPUComponent
}


gl_GPUComponent :: struct {
    vao, vbo, ebo: u32,
    expressed_vert, expressed_ind: bool,
    program: ShaderProgram
}

vl_GPUComponent :: struct {
    vlwhatthefuckwouldgohere: u32
}


/*
   Returns if a specific GPU component is able to be drawn to the screen
   Returns an error code (binary representation more apt)
   OpenGL:
    0 -> drawable
    0001 -> vertices not expressed
    0010 -> indices not expressed
    0100 -> program not attached
    
    A result of 0110 means 0010 | 0100 e.g. vertices not expressed U program not attached
*/
component_is_drawable_ :: #type proc(component: GPUComponent) -> u32
component_is_drawable: component_is_drawable_ = gl_component_is_drawable

gl_component_is_drawable :: proc(component: GPUComponent) -> u32 {
    comp := component.(gl_GPUComponent)
    return (u32(!comp.expressed_vert)) | (u32(!comp.expressed_ind) << 1) | (u32(!comp.program.expressed) << 2)
}



release_gpu_component :: proc(component: GPUComponent) {
    switch RENDER_API {
    case .OPENGL: 
        gl_component := component.(gl_GPUComponent)

        gl.DeleteVertexArrays(1, &gl_component.vao)
        gl.DeleteBuffers(1, &gl_component.vbo)
        gl.DeleteBuffers(1, &gl_component.ebo)
        gl.DeleteProgram(u32(gl_component.program.id.(i32)))
    case .VULKAN: vulkan_not_supported();
    }
}

//


DEFAULT_DRAW_PROPERTIES: DrawProperties
DrawProperties :: struct {  // todo limit to opengl, makes development easier and trying to predict how vulkan works is stupid
    mesh: model.Mesh,
    indices: model.IndexData,
    gpu_component: GPUComponent,
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
