package render

import gl "vendor:OpenGL"

import "../resource"
import dbg "../debug"
import "../utils"

import "core:log"
import "core:mem"
import "base:runtime"


release_mesh :: proc(mesh: resource.Mesh) {
    mesh := mesh
    gl.DeleteVertexArrays(1, &mesh.gl_component.vao.?)
    gl.DeleteBuffers(1, &mesh.gl_component.vbo.?)
    gl.DeleteBuffers(1, &mesh.gl_component.ebo.?)
}

release_model :: proc(model: resource.Model) {
    for mesh in model.meshes do release_mesh(mesh)
}

// Pretty useless
transfer_model :: proc(manager: ^resource.ResourceManager, model: resource.Model, destroy_after_transfer := true) -> (ok: bool) {
    dbg.log(.INFO, "Transferring model")

    for &mesh in model.meshes do transfer_mesh(manager, &mesh, destroy_after_transfer) or_return

    return
}

@(private)
transfer_mesh :: proc(manager: ^resource.ResourceManager, mesh: ^resource.Mesh, destroy_after_transfer := true, loc := #caller_location) -> (ok: bool) {
    if mesh.gl_component.vao == nil do create_and_transfer_vao(&mesh.gl_component.vao)
    else do bind_vao(mesh.gl_component.vao.?)

    if mesh.gl_component.vbo == nil {
        layout := resource.get_vertex_layout(manager, mesh.layout) or_return
        create_and_transfer_vbo(&mesh.gl_component.vbo, mesh.vertex_data, layout.infos) or_return
        if destroy_after_transfer do delete(mesh.vertex_data)
    }
    else do bind_vbo(mesh.gl_component.vbo.?)

    if mesh.gl_component.ebo == nil {
        create_and_transfer_ebo(&mesh.gl_component.ebo, mesh) or_return
        if destroy_after_transfer do delete(mesh.index_data)
    }
    else do bind_ebo(mesh.gl_component.ebo.?)

    return true
}


/*
    Binds VAO
    Assumes bound vao
    Assumes not already transferred
*/
@(private)
create_and_transfer_vao :: proc{ create_and_transfer_vao_raw, create_and_transfer_vao_maybe }

@(private)
create_and_transfer_vao_raw :: proc(vao: ^u32) {
    gl.GenVertexArrays(1, vao)
    bind_vao(vao^)
}

@(private)
create_and_transfer_vao_maybe :: proc(vao: ^Maybe(u32)) {
    new_vao: u32
    create_and_transfer_vao_raw(&new_vao)
    vao^ = new_vao
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
create_and_transfer_vbo :: proc{ create_and_transfer_vbo_maybe, create_and_transfer_vbo_raw }

@(private)
create_and_transfer_vbo_maybe :: proc(vbo: ^Maybe(u32), vertex_data: resource.VertexData, layout: []resource.MeshAttributeInfo) -> (ok: bool) {
    new_vbo: u32
    ok = create_and_transfer_vbo_raw(&new_vbo, vertex_data, layout)
    vbo^ = new_vbo
    return ok
}

@(private)
create_and_transfer_vbo_raw :: proc(vbo: ^u32, vertex_data: resource.VertexData, layout: []resource.MeshAttributeInfo) -> (ok: bool) {
    if len(vertex_data) == 0 {
        dbg.log(.ERROR, "No vertices given to express");
        return
    }

    gl.GenBuffers(1, vbo)
    bind_vbo(vbo^)

    total_byte_stride: u32 = 0; for attribute_layout in layout do total_byte_stride += attribute_layout.byte_stride

    transfer_buffer_data(gl.ARRAY_BUFFER, raw_data(vertex_data), len(vertex_data) * size_of(f32), BufferUsage{ .WRITE_ONCE_READ_MANY, .DRAW })

    offset, current_ind: u32 = 0, 0
    for attribute_info in layout {
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
create_and_transfer_ebo :: proc{ create_and_transfer_ebo_maybe, create_and_transfer_ebo_raw }

@(private)
create_and_transfer_ebo_maybe :: proc(ebo: ^Maybe(u32), data: ^resource.Mesh) -> (ok: bool) {
    new_ebo: u32
    ok = create_and_transfer_ebo_raw(&new_ebo, data)
    ebo^ = new_ebo
    return ok
}

@(private)
create_and_transfer_ebo_raw :: proc(ebo: ^u32, data: ^resource.Mesh) -> (ok: bool) {
    dbg.log(.INFO, "Expressing gl mesh indices")
    if len(data.index_data) == 0 {
        dbg.log(.ERROR, "Cannot express 0 indices")
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
GPUTexture :: Maybe(u32)

transfer_texture :: proc(tex: ^resource.Texture, destroy_after_transfer := true, loc := #caller_location) -> (ok: bool) {

    if tex == nil {
        dbg.log(.ERROR, "Texture given as nil", loc=loc)
        return
    }

    if tex.gpu_texture != nil do return true

    gpu_tex := make_texture(tex^)
    if gpu_tex == nil {
        dbg.log(dbg.LogLevel.ERROR, "make_texture returned nil texture")
        return
    }

    if tex.image.pixel_data != nil && destroy_after_transfer do resource.destroy_pixel_data(&tex.image)

    tex.gpu_texture = gpu_tex

    return true
}

make_texture :: proc{ make_texture_, make_texture_raw }

// resource.Texture refers specifically to material textures - therefore they will be colour attachments and will use RGBA16F
make_texture_ :: proc(tex: resource.Texture) -> (texture: GPUTexture) {
    return make_texture_raw(tex.image.w, tex.image.h, tex.image.pixel_data)
}

make_texture_raw :: proc(w, h: i32, data: rawptr = nil, internal_format: i32 = gl.RGBA8, lod: i32 = 0, format: u32 = gl.RGBA, type: u32 = gl.UNSIGNED_BYTE) -> (texture: GPUTexture) {
    dbg.log(.INFO, "Making new texture")
    id: u32
    gl.GenTextures(1, &id)
    texture = id

    gl.BindTexture(gl.TEXTURE_2D, id)
    gl.TexImage2D(gl.TEXTURE_2D, lod, internal_format, w, h, 0, format, type, data)

    // Todo make support for this elsewhere
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    return
}

release_texture :: proc(texture: ^GPUTexture) {
    if id, id_ok := texture.?; id_ok do gl.DeleteTextures(1, &id)
}

bind_texture :: proc(texture_unit: u32, texture: GPUTexture, loc := #caller_location) -> (ok: bool) {
    if texture == nil {
        dbg.log(dbg.LogLevel.ERROR, "Texture to bind at unit %d is not transferred to gpu", texture_unit, loc=loc)
        return
    }
    if texture_unit > 31 {
        dbg.log(dbg.LogLevel.ERROR, "Texture unit is greater than 31 - active textures limit exceeded")
        return
    }

    gl.ActiveTexture(u32(gl.TEXTURE0) + texture_unit)
    gl.BindTexture(gl.TEXTURE_2D, texture.?)
    return true
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

make_shader_buffer :: proc(data: rawptr, data_size: int, type: ShaderBufferType, shader_binding: u32, usage: BufferUsage) -> (buffer: ShaderBuffer) {
    dbg.log(dbg.LogLevel.INFO, "Creating shader buffer of type: %v and binding: %d", type, shader_binding)

    id: u32
    gl.GenBuffers(1, &id)
    buffer.id = id
    buffer.type = type

    glenum_type: u32 = type == .UBO ? gl.UNIFORM_BUFFER : gl.SHADER_STORAGE_BUFFER
    transfer_buffer_data(glenum_type, data, data_size, usage=usage, buffer_id=id)
    gl.BindBufferBase(glenum_type, shader_binding, id)

    return
}


/*
    Does not bind, create or validate
    Set update to true when updating in a frame rather than setting the buffer up
*/
transfer_buffer_data :: proc{ transfer_buffer_data_of_type, transfer_buffer_data_of_target }

transfer_buffer_data_of_type :: proc(type: ShaderBufferType, data: rawptr, #any_int data_size: int, usage: BufferUsage = {},  update := false, data_offset := 0, buffer_id: Maybe(u32) = nil) {
    target: u32 = type == .UBO ? gl.UNIFORM_BUFFER : gl.SHADER_STORAGE_BUFFER
    if buffer_id != nil do gl.BindBuffer(target, buffer_id.?)
    if data_offset != 0 || update {
        gl.BufferSubData(target, data_offset, data_size, data)
        return
    }
    gl.BufferData(target, data_size, data, buffer_usage_to_glenum(usage))
}

transfer_buffer_data_of_target :: proc(target: u32, data: rawptr, #any_int data_size: int, usage: BufferUsage = {},  update := false, data_offset := 0, buffer_id: Maybe(u32) = nil) {
    if buffer_id != nil do gl.BindBuffer(target, buffer_id.?)
    if data_offset != 0 || update {
        gl.BufferSubData(target, data_offset, data_size, data)
        return
    }
    gl.BufferData(target, data_size, data, buffer_usage_to_glenum(usage))
}


// Compiles and links shaders in program
transfer_shader_program :: proc(manager: ^resource.ResourceManager, program: ^resource.ShaderProgram) -> (ok: bool) {
    if program.id != nil do return true

    dbg.log(dbg.LogLevel.INFO, "Transferring shader program")

    shader_ids := make([dynamic]u32, len(program.shaders))
    defer delete(shader_ids)

    i := 0
    for _, given_shader in program.shaders {
        shader := resource.get_shader(manager, given_shader) or_return
        id := compile_shader(shader) or_return
        shader_ids[i] = id
        i += 1
    }

    program.id = gl.create_and_link_program(shader_ids[:]) or_return
    return true
}

compile_shader :: proc(shader: ^resource.Shader) -> (id: u32, ok: bool) {
    if shader.id != nil do return shader.id.?, true

    dbg.log(dbg.LogLevel.INFO, "Compiling shader of type %v", shader.type)
    if !shader.source.is_available_as_string || len(shader.source.string_source) == 0 {
        dbg.log(dbg.LogLevel.INFO, "String shader source not provided in shader compilation")
        return
    }

    id, ok = gl.compile_shader_from_source(shader.source.string_source, resource.conv_gl_shader_type(shader.type))
    if !ok {
        dbg.log(dbg.LogLevel.ERROR, "Could not compile shader source of shader type %v", shader.type)
        return
    }

    shader.id = id
    ok = true
    return
}


attach_program :: proc(program: resource.ShaderProgram, loc := #caller_location) {
    if program_id, id_ok := utils.unwrap_maybe(program.id); !id_ok {
        dbg.log(dbg.LogLevel.INFO, "Shader program not yet created")
        return
    }
    else{
        gl.UseProgram(program_id)
    }
}


issue_single_element_draw_call :: proc(#any_int indices_count: i32) {
    gl.DrawElements(gl.TRIANGLES, indices_count, gl.UNSIGNED_INT, nil)
}


@(private)
conv_blend_parameter :: proc(param: BlendParameter) -> u32 {
    switch param {
        case .ZERO: return gl.ZERO
        case .ONE: return gl.ONE
        case .SOURCE: return gl.SRC_COLOR
        case .ONE_MINUS_SOURCE: return gl.ONE_MINUS_SRC_COLOR
        case .SOURCE_ALPHA: return gl.SRC_ALPHA
        case .ONE_MINUS_SOURCE_ALPHA: return gl.ONE_MINUS_SRC_ALPHA
        case .DEST: return gl.DST_COLOR
        case .ONE_MINUS_DEST: return gl.ONE_MINUS_DST_COLOR
        case .DEST_ALPHA: return gl.ONE_MINUS_DST_ALPHA
        case .ONE_MINUS_DEST_ALPHA: return gl.ONE_MINUS_DST_ALPHA
        case .CONSTANT_COLOUR: return gl.CONSTANT_COLOR
        case .ONE_MINUS_CONSTANT_COLOUR: return gl.ONE_MINUS_CONSTANT_COLOR
        case .CONSTANT_ALPHA: return gl.CONSTANT_ALPHA
        case .ONE_MINUS_CONSTANT_ALPHA: return gl.ONE_MINUS_CONSTANT_ALPHA
        case .ALPHA_SATURATE: return gl.SRC_ALPHA_SATURATE
    }
    return 0
}

set_blend_func :: proc(func: BlendFunc) {
    gl.BlendFunc(conv_blend_parameter(func.source), conv_blend_parameter(func.dest))
}

set_default_blend_func :: proc() {
    gl.BlendFunc(gl.ONE, gl.ZERO)
}

@(private)
conv_face :: proc(face: Face) -> u32 {
    switch face {
        case .FRONT: return gl.FRONT
        case .BACK: return gl.BACK
        case .FRONT_AND_BACk: return gl.FRONT_AND_BACK
    }
    return 0
}

cull_geometry_faces :: proc(face: Face) {
    gl.Enable(gl.CULL_FACE)
    gl.CullFace(conv_face(face))
}

set_face_culling :: proc(cull: bool) {
    // if cull do gl.Enable(gl.CULL_FACE)
    // else do gl.Disable(gl.CULL_FACE)
}

set_depth_test :: proc(test: bool) {
    if test do gl.Enable(gl.DEPTH_TEST)
     else do gl.Disable(gl.DEPTH_TEST)
}

set_stencil_test :: proc(test: bool) {
    if test do gl.Enable(gl.STENCIL_TEST)
    else do gl.Disable(gl.STENCIL_TEST)
}

set_front_face :: proc(mode: FrontFaceMode) {
    if mode == .CLOCKWISE do gl.FrontFace(gl.CW)
    else do gl.FrontFace(gl.CCW)
}

enable_colour_writes :: proc(r, g, b, a: bool) {
    gl.ColorMask(r, g, b, a)
}

enable_depth_writes :: proc(depth: bool) {
    gl.DepthMask(depth)
}

enable_stencil_wrties :: proc(stencil: bool) {
    gl.StencilMask(stencil ? 0xFF : 0x0)
}

@(private)
conv_poly_display_mode :: proc(mode: PolygonDisplayMode) -> u32 {
    switch mode {
        case .FILL: return gl.FILL
        case .LINE: return gl.LINE
        case .POINT: return gl.POINT
    }
    return 0
}

set_polygon_mode :: proc(mode: PolygonMode) {
    gl.PolygonMode(conv_face(mode.face), conv_poly_display_mode(mode.display_mode))
}

set_default_polygon_mode :: proc() {
    gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
}