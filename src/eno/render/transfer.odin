package gpu

import gl "vendor:OpenGL"

import "../model"
import dbg "../debug"
import "../shader"

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


transfer_model :: proc(model: model.Model) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Transferring model")

    express_mesh_with_indices(draw_properties) or_return

    // currently just gl_express_mesh_with_indices
    // todo: add shader support

    return
}


express_mesh_with_indices :: proc(mesh: ^model.Mesh) -> (ok: bool) {


    gl.GenVertexArrays(1, &mesh.gl_component.vao)
    gl.BindVertexArray(mesh.gl_component.vao)

    if !gpu_component.expressed_vert {
        // Express ebo
        create_and_express_vbo(&mesh.gl_component.vbo, mesh) or_return
        mesh.gl_component.vbo.transferred = true
    }

    if !gpu_component.expressed_ind {
        // Express ebo
         create_and_express_ebo(&gpu_component.ebo, mesh) or_return
         mesh.gl_component.ebo.transferred = true
    }


    ok = true
    return
}


/*
    Assumes not expressed
    Assumes bound vao
*/
@(private)
create_and_express_vbo :: proc(vbo: ^u32, data: model.Mesh) -> (ok: bool) {
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
    add_buffer_data(gl.ARRAY_BUFFER, data.vertex_data, { .WRITE_ONCE_READ_MANY, .DRAW })

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
create_and_express_ebo :: proc(ebo: ^u32, data: model.Mesh) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing gl mesh indices")
    if len(data.index_data) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Cannot express 0 indices")
        return
    }

    gl.GenBuffers(1, ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo^)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(data.index_data) * size_of(u32), raw_data(data.index_data), gl.STATIC_DRAW)

    ok = true
    return
}


/*
gl_draw_elements :: proc(draw_properties: ^DrawProperties) {
    // todo add checks for expressedness of components
    comp := draw_properties.gpu_component.(gl_GPUComponent)
    gl.BindVertexArray(comp.vao)
    gl.UseProgram(u32(comp.program.id.(i32)))
    gl.DrawElements(gl.TRIANGLES, i32(len(draw_properties.indices.raw_data)), gl.UNSIGNED_INT, nil)
}
*/


/* 2D Single sample texture */
Texture :: struct {
    id: Maybe(u32)
}

make_texture :: proc(lod: i32 = 0, interal_type: i32 = gl.RGBA,  w, h: i32, format: u32 = gl.RGBA, type: u32 = gl.FLOAT, data: rawptr = nil) -> (texture: Texture) {
    gl.GenTextures(1, &texture.id)
    gl.BindTexture(gl.TEXTURE_2D, texture.id)
    gl.TexImage2D(gl.TEXTURE_2D, lod, internal_type, w, h, 0, format, type, data)
}


// Can add more if needed - this exists to not directly use the glenum
BufferAccessFrequency :: enum {
    WRITE_ONCE_READ_MANY,
    WRITE_MANY_READ_MANY
}

BufferAccessType :: enum {
    DRAW,
    READ,
    COPY
}

BufferUsage :: struct {
    frequency: BufferAccessFrequency,
    type: BufferAccessType
}

@(private)
buffer_usage_to_glenum :: proc(usage: BufferUsage) -> (res: u32) {
    switch usage.frequency {
        case .WRITE_ONCE_READ_MANY:
            switch usage.type {
                case .COPY:
                    res = gl.STATIC_COPY
                case .READ:
                    res = gl.STATIC_READ
                case .DRAW:
                    res = gl.STATIC_DRAW
            }

        case .WRITE_MANY_READ_MANY:
            switch usage.type {
                case .COPY:
                    res = gl.DYNAMIC_COPY
                case .READ:
                    res = gl.DYNAMIC_READ
                case .DRAW:
                    res = gl.DYNAMIC_DRAW
            }
    }
    return
}


ShaderStorageBuffer :: struct {
    id: Maybe(u32),
    shader_binding: u32,
    usage: BufferUsage
}

make_shader_storage_buffer_dynamic :: proc(data: $T/[dynamic]$E, shader_binding: u32, usage: BufferUsage) -> (buffer: ShaderStorageBuffer) {
    make_shader_storage_buffer_slice(data[:], shader_binding, usage)
}

make_shader_storage_buffer_slice :: proc(data: $T/[]$E, shader_binding: u32, usage: BufferUsage) -> (buffer: ShaderStorageBuffer) {
    
}


/*
    Does not bind, create or validate
*/
add_buffer_data :: proc{ add_buffer_data_slice, add_buffer_data_dynamic }

@(private)
add_buffer_data_dynamic :: proc(target: u32, data: $T/[dynamic]$E, usage: BufferUsage, data_offset := 0) {
    add_bufer_data_slice(target, data[:], usage, data_offset)
}

@(private)
add_buffer_data_slice :: proc(target: u32, data: $T/[]$E, usage: BufferUsage, data_offset := 0) {
    data_size := size_of(E) * len(data)
    if data_range_start != 0 || data_range_end != 0 {
        gl.BufferSubData(target, data_offset, data_size, data)
    }
    gl.BufferData(target, data_size, data, buffer_usage_to_glenum(usage))
}