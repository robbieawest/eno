package render

import gl "vendor:OpenGL"

import "../resource"
import dbg "../debug"
import "../shader"
import "../utils"


// todo look at shaders for this
release_mesh :: proc(mesh: ^resource.Mesh) {
    delete(mesh.vertex_data)
    delete(mesh.index_data)
    gl.DeleteVertexArrays(1, &mesh.gl_component.vao.?)
    gl.DeleteBuffers(1, &mesh.gl_component.vbo.?)
    gl.DeleteBuffers(1, &mesh.gl_component.ebo.?)
}

release_model :: proc(model: ^resource.Model) {
    for &mesh in model.meshes do release_mesh(&mesh)
}


transfer_model :: proc(manager: ^resource.ResourceManager, model: resource.Model, transfer_material_shader: bool) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Transferring model")

    for &mesh in model.meshes do transfer_mesh(manager, &mesh, transfer_material_shader, transfer_material_shader)

    return
}

// Binds all resoucres
transfer_mesh :: proc(manager: ^resource.ResourceManager, mesh: ^resource.Mesh, transfer_material_shader: bool, compile: bool, loc := #caller_location) -> (ok: bool) {

    if mesh.gl_component.vao == nil do create_and_transfer_vao(&mesh.gl_component.vao.?)
    else do bind_vao(mesh.gl_component.vao.?)
    if mesh.gl_component.vbo == nil do create_and_transfer_vbo(&mesh.gl_component.vbo.?, mesh) or_return
    else do bind_vbo(mesh.gl_component.vbo.?)
    if mesh.gl_component.ebo == nil do create_and_transfer_ebo(&mesh.gl_component.ebo.?, mesh) or_return
    else do bind_ebo(mesh.gl_component.ebo.?)

    mat_id, mat_ok := mesh.material.?; if !mat_ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "material not found for mesh")
        return
    }
    material := resource.get_material(manager, mat_id)
    if transfer_material_shader {
        if material == nil {
            dbg.debug_point(dbg.LogLevel.ERROR, "Mesh material id %d does not exist in the manager", mesh.material, loc=loc)
            return
        }

        // if material.lighting_shader == nil do material.lighting_shader = create_lighting_shader(material^, compile)
    }
    program := resource.get_shader(manager, material.lighting_shader.?)
    bind_program(program.id.?)

    ok = true
    return
}

/*
    Binds VAO
    Assumes bound vao
    Assumes not already transferred
*/
@(private)
create_and_transfer_vao :: proc(vao: ^u32) {
    gl.GenVertexArrays(1, vao)
    bind_vao(vao^)
}

@(private)
bind_vao :: proc(vao: u32) {
    gl.BindVertexArray(vao)
}

/*
    Assumes not already transferred
    Assumes bound vao
    Binds VBO
*/
@(private)
create_and_transfer_vbo :: proc(vbo: ^u32, data: ^resource.Mesh) -> (ok: bool) {
    if len(data.vertex_data) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "No vertices given to express");
        return
    }

    gl.GenBuffers(1, vbo)
    bind_vbo(vbo^)

    total_byte_stride: u32 = 0; for attribute_layout in data.layout do total_byte_stride += attribute_layout.byte_stride

    transfer_buffer_data(gl.ARRAY_BUFFER, raw_data(data.vertex_data), len(data.vertex_data) * size_of(f32), { .WRITE_ONCE_READ_MANY, .DRAW })

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

@(private)
bind_vbo :: proc(vbo: u32) {
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
}


/*
    Assumes not expressed
    Assumes bound vao
    Binds EBO
*/
@(private)
create_and_transfer_ebo :: proc(ebo: ^u32, data: ^resource.Mesh) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing gl mesh indices")
    if len(data.index_data) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Cannot express 0 indices")
        return
    }

    gl.GenBuffers(1, ebo)
    bind_ebo(ebo^)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(data.index_data) * size_of(u32), raw_data(data.index_data), gl.STATIC_DRAW)

    ok = true
    return
}

@(private)
bind_ebo :: proc(ebo: u32) {
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
}

bind_program :: proc(program: u32) {
    gl.UseProgram(program)
}


/* 2D single sample texture for gpu package internal use */
Texture :: Maybe(u32)

// Todo add sampling support and give channels input instead of internal_format
make_texture :: proc(lod: i32 = 0, internal_format: i32 = gl.RGBA, w, h: i32, format: u32 = gl.RGBA, type: u32 = gl.FLOAT, data: rawptr = nil) -> (texture: Texture) {
    id: u32
    gl.GenTextures(1, &id)
    texture = id

    gl.BindTexture(gl.TEXTURE_2D, id)
    gl.TexImage2D(gl.TEXTURE_2D, lod, internal_format, w, h, 0, format, type, data)

    return
}

destroy_texture :: proc(texture: ^Texture) {
    if id, id_ok := texture.?; id_ok do gl.DeleteTextures(1, &id)
}

bind_texture :: proc(texture_unit: u32, texture: Texture) {
    gl.ActiveTexture(u32(gl.TEXTURE0) + texture_unit)
    gl.BindTexture(gl.TEXTURE_2D, texture.?)
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


ShaderBufferType :: enum{ SSBO, UBO }
ShaderBuffer :: struct {
    id: Maybe(u32),
    shader_binding: u32,
    usage: BufferUsage,
    type: ShaderBufferType
}

make_shader_buffer :: proc(data: rawptr, type: ShaderBufferType, shader_binding: u32, usage: BufferUsage) -> (buffer: ShaderBuffer) {
    id: u32
    gl.GenBuffers(1, &id)
    buffer.id = id
    buffer.type = type

    glenum_type: u32 = type == .UBO ? gl.UNIFORM_BUFFER : gl.SHADER_STORAGE_BUFFER
    gl.BindBuffer(glenum_type, id)
    transfer_buffer_data(glenum_type, data, buffer_usage_to_glenum(usage))
    gl.BindBufferBase(glenum_type, shader_binding, id)

    return
}


/*
    Does not bind, create or validate
    Set update to true when updating in a frame rather than setting the buffer up
*/
transfer_buffer_data :: proc(target: u32, data: rawptr, #any_int data_size: int, usage: BufferUsage = {},  update := false, data_offset := 0) {
    if data_offset != 0 || update {
        gl.BufferSubData(target, data_offset, data_size, data)
    }
    gl.BufferData(target, data_size, data, buffer_usage_to_glenum(usage))
}


// Shaders
transfer_shader :: proc(program: ^shader.ShaderProgram) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing shader")

    if program.id != nil do return true

    shader_ids := make([dynamic]u32, len(program.shaders))
    defer delete(shader_ids)

    i := 0
    for _, &given_shader in program.shaders {
        dbg.debug_point(dbg.LogLevel.INFO, "Expressing source")
        if !given_shader.source.is_available_as_string || len(given_shader.source.string_source) == 0 {
            dbg.debug_point(dbg.LogLevel.INFO, "Shader source was not provided prior to transfer_shader, building new")
            shader.supply_shader_source(&given_shader) or_return
        }

        id, compile_ok := gl.compile_shader_from_source(given_shader.source.string_source, shader.conv_gl_shader_type(given_shader.type))
        if !compile_ok {
            dbg.debug_point(dbg.LogLevel.ERROR, "Could not compile shader source: %s", given_shader.source)
            return ok
        }
        shader_ids[i] = id
    }

    program.id = gl.create_and_link_program(shader_ids[:]) or_return
    ok = true
    return
}

attach_program :: proc(program: shader.ShaderProgram, loc := #caller_location) {
    if program_id, id_ok := utils.unwrap_maybe(program.id); !id_ok {
        dbg.debug_point(dbg.LogLevel.INFO, "Shader program not yet created")
        return
    }
    else{
        gl.UseProgram(program_id)
    }
}


issue_single_element_draw_call :: proc(#any_int indices_count: i32) {
    gl.DrawElements(gl.TRIANGLES, indices_count, gl.UNSIGNED_INT, nil)
}