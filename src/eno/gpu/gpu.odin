package gpu

import gl "vendor:OpenGL"

import "../model"
import "../shader"
import dbg "../debug"

import "core:testing"
import "core:log"
import "core:strings"
import glm "core:math/linalg/glsl"


GraphicsAPI :: enum { OPENGL, VULKAN } //Making it easy for the future
RENDER_API: GraphicsAPI = GraphicsAPI.OPENGL


// Defined way to store VAO, VBO, EBO in the entity component system
// A link to release_gpu_components should be stored as a component when creating an entity with GPUComponents as another component
// ToDo: Maybe combine these into a single struct?

GPUComponent :: union #no_nil {
    gl_GPUComponent,
    vl_GPUComponent
}



gl_GPUComponent :: struct {
    vao, vbo, ebo: u32,
    expressed_vert, expressed_ind: bool,
    program: shader.ShaderProgram
}

vl_GPUComponent :: struct {
    vlwhatthefuckwouldgohere: u32
}

// ToDo add proper checks for expressedness and drawability for components

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
    return (u32(comp.expressed_vert)) | (u32(comp.expressed_ind) << 1) | (u32(comp.program.expressed) << 2)
}



release_gpu_component :: proc(component: GPUComponent) {
    switch RENDER_API {
    case .OPENGL: 
        gl_component := component.(gl_GPUComponent)

        gl.DeleteVertexArrays(1, &gl_component.vao)
        gl.DeleteBuffers(1, &gl_component.vbo)
        gl.DeleteBuffers(1, &gl_component.ebo)
        gl.DeleteProgram(gl_component.program.id.(u32))
        free(&gl_component)
    case .VULKAN: vulkan_not_supported();
    }
}

//


DEFAULT_DRAW_PROPERTIES: DrawProperties
DrawProperties :: struct {
    mesh: model.Mesh,
    indices: model.IndexData,
    gpu_component: GPUComponent,
}


// Procedures to express mesh structures on the GPU, a shader is assumed to already be attached

express_mesh_with_indices :: proc(mesh: ^model.Mesh, index_data: ^model.IndexData) -> (gpu_component: GPUComponent, ok: bool) {

    switch RENDER_API {
    case .OPENGL:
        gl_def_comp: gl_GPUComponent
        gpu_component = gl_def_comp
        
    case .VULKAN: vulkan_not_supported(); return gpu_component, ok
    } 

    ok = express_mesh_vertices(mesh, &gpu_component)
    if !ok do return gpu_component, ok

    ok = express_indices(index_data, &gpu_component)
    if !ok do return gpu_component, ok 
    

    return gpu_component, true
}


//*Likely should use express_mesh_with_indices instead
express_mesh_vertices_ :: #type proc(mesh: ^model.Mesh, component: ^GPUComponent) -> (ok: bool)
express_mesh_vertices: express_mesh_vertices_ = gl_express_mesh_vertices


@(private)
gl_express_mesh_vertices :: proc(mesh: ^model.Mesh, component: ^GPUComponent) -> (ok: bool) {
    if len(mesh.vertices) == 0 { log.errorf("%s: No vertices given to express", #procedure); return ok }

    gl_component := &component.(gl_GPUComponent)
    gl_component.expressed_vert = true

    gl.GenVertexArrays(1, &gl_component.vao)
    gl.GenBuffers(1, &gl_component.vbo)
    
    gl.BindVertexArray(gl_component.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, gl_component.vbo)

    stride: int = len(mesh.vertices[0].raw_data) * size_of(f32)
    gl.BufferData(gl_component.vbo, len(mesh.vertices) * stride, raw_data(mesh.vertices), gl.STATIC_DRAW)

    offset, current_ind: u32 = 0, 0
    for size in mesh.layout.sizes {
        gl.EnableVertexAttribArray(current_ind)
        gl.VertexAttribPointer(current_ind, i32(size), gl.FLOAT, gl.FALSE, i32(stride), uintptr(offset))

        offset += u32(size)
        current_ind += 1
    }

    return true
}


//*Likely should use express_mesh_with_indices instead
express_indices_ :: #type proc(index_data: ^model.IndexData, component: ^GPUComponent) -> (ok: bool)
express_indices: express_indices_ = gl_express_indices

@(private)
gl_express_indices :: proc(index_data: ^model.IndexData, component: ^GPUComponent) -> (ok: bool){
    gl_component := &component.(gl_GPUComponent)
    gl_component.expressed_ind = true

    gl.GenBuffers(1, &gl_component.ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_component.ebo)
    gl.BufferData(gl_component.ebo, len(index_data.raw_data) * size_of(u32), raw_data(index_data.raw_data), gl.STATIC_DRAW)
    
    return true
}

//


draw_elements_ :: #type proc(draw_properties: ^DrawProperties)
draw_elements: draw_elements_ = gl_draw_elements

gl_draw_elements :: proc(draw_properties: ^DrawProperties) {
    comp := draw_properties.gpu_component.(gl_GPUComponent)
    gl.BindVertexArray(comp.vao)
    gl.UseProgram(comp.program.id.(u32))
    gl.DrawElements(gl.TRIANGLES, i32(len(draw_properties.indices.raw_data)), gl.UNSIGNED_INT, nil)
}


express_shader :: proc(program: ^shader.ShaderProgram) -> (ok: bool) {
    using shader
    if RENDER_API == .VULKAN {
        vulkan_not_supported()
        return ok
    }
    if program.expressed do return true

    dbg.debug_point(dbg.LogInfo{ msg = "Expressing Shader", level = .INFO })

    switch (RENDER_API) {
    case .OPENGL:
        shader_ids := make([dynamic]u32, len(program.sources))
        defer delete(shader_ids)

        for shader_source, i in program.sources {
            dbg.debug_point()
            id, compile_ok := gl.compile_shader_from_source(shader_source.compiled_source, conv_gl_shader_type(shader_source.type))
            if !compile_ok {
                log.errorf("Could not compile shader source: %s", shader_source.compiled_source)
                return ok
            }
            shader_ids[i] = id
        }

        program.id = gl.create_and_link_program(shader_ids[:]) or_return
        program.expressed = true
    case .VULKAN:
        vulkan_not_supported()
        return ok
    }
    return true
}


// Updating shader uniforms



shader_uniform_update_mat4_ :: #type proc(draw_properties: ^DrawProperties, uniform_tag: string, mat: [^]f32) -> (ok: bool) 
shader_uniform_update_mat4: shader_uniform_update_mat4_ = gl_shader_uniform_update_mat4

gl_shader_uniform_update_mat4 :: proc(draw_properties: ^DrawProperties, uniform_tag: string, mat: [^]f32) -> (ok: bool){
    gpu_comp := &draw_properties.gpu_component.(gl_GPUComponent)
    program: ^shader.ShaderProgram = &gpu_comp.program

    if !program.expressed {
        dbg.debug_point(dbg.LogInfo{ msg = "Shader not yet expressed", level = .ERROR })
        return ok
    }
    dbg.debug_point()

    tag_cstr := strings.clone_to_cstring(uniform_tag)
    program_id := program.id.(u32)

    gl.UseProgram(program_id)
    loc := gl.GetUniformLocation(program_id, tag_cstr)
    if loc == -1 {
        dbg.debug_point(dbg.LogInfo{ msg = "Shader uniform does not exist", level = .ERROR })
        return ok
    }
    gl.UniformMatrix4fv(loc, 1, false, mat)

    return true
}

//


vulkan_not_supported :: proc(location := #caller_location) { log.errorf("%v: Vulkan not supported", location) }
