package render

import gl "vendor:OpenGL"

import "../resource"
import dbg "../debug"
import "../utils"

import "core:log"
import "core:mem"
import "base:runtime"


release_mesh :: proc(mesh: resource.Mesh) {
    release_gl_component(mesh.gl_component)
}

release_gl_component :: proc(comp: resource.GLComponent) {
    comp := comp
    using comp
    if vao != nil do gl.DeleteVertexArrays(1, &vao.?)
    if vbo != nil do gl.DeleteBuffers(1, &vbo.?)
    if ebo != nil do gl.DeleteBuffers(1, &ebo.?)
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
    dbg.log(.INFO, "Creating and transferring vao")
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
    dbg.log(.INFO, "Creating and transferring vbo")
    if len(vertex_data) == 0 {
        dbg.log(.ERROR, "No vertices given to express");
        return
    }

    gl.GenBuffers(1, vbo)
    bind_vbo(vbo^)

    total_byte_stride: u32 = 0; for attribute_layout in layout do total_byte_stride += attribute_layout.byte_stride

    transfer_buffer_data(gl.ARRAY_BUFFER, raw_data(vertex_data), len(vertex_data) * size_of(f32), BufferUsage{ .WRITE_ONCE_READ_MANY, .DRAW })

    for attrib in 0..<max_vertex_attributes() do gl.DisableVertexAttribArray(attrib);

    offset, current_ind: u32 = 0, 0
    for attribute_info in layout {
        gl.VertexAttribPointer(current_ind, i32(attribute_info.float_stride), gl.FLOAT, gl.FALSE, i32(total_byte_stride), uintptr(offset))
        gl.EnableVertexAttribArray(current_ind)

        offset += attribute_info.byte_stride
        current_ind += 1
    }

    ok = true
    return
}

@(private)
bind_vbo :: proc(vbo: u32) {
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
}

@(private)
max_vertex_attributes :: proc() -> u32 {
    max: i32
    gl.GetIntegerv(gl.MAX_VERTEX_ATTRIBS, &max)
    return u32(max)
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
    dbg.log(.INFO, "Creating and transferring ebo")
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

transfer_texture :: proc(
    tex: ^resource.Texture,
    internal_format: i32 = gl.RGBA8,
    lod: i32 = 0,
    format: u32 = gl.RGBA,
    type: u32 = gl.UNSIGNED_BYTE,
    generate_mipmap := false,
    destroy_after_transfer := true,
    loc := #caller_location
) -> (ok: bool) {

    if tex == nil {
        dbg.log(.ERROR, "Texture given as nil", loc=loc)
        return
    }

    if tex.gpu_texture != nil do return true

    gpu_tex := make_texture(tex^, internal_format, lod, format, type, generate_mipmap, loc)
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
make_texture_ :: proc(
    tex: resource.Texture,
    internal_format: i32 = gl.RGBA8,
    lod: i32 = 0,
    format: u32 = gl.RGBA,
    type: u32 = gl.UNSIGNED_BYTE,
    generate_mipmap := false,
    loc := #caller_location
) -> (texture: GPUTexture) {
    return make_texture_raw(tex.image.w, tex.image.h, tex.image.pixel_data, internal_format, lod, format, type, tex.type, tex.properties, generate_mipmap, loc)
}

make_texture_raw :: proc(
    w, h: i32,
    data: rawptr = nil,
    internal_format: i32 = gl.RGBA8,
    lod: i32 = 0,
    format: u32 = gl.RGBA,
    type: u32 = gl.UNSIGNED_BYTE,
    texture_type: resource.TextureType = .TWO_DIM,
    texture_properties: resource.TextureProperties = {},
    generate_mipmap := false,
    loc := #caller_location
) -> (texture: GPUTexture) {
    dbg.log(.INFO, "Making new texture, w: %d, h: %d", w, h, loc=loc)
    id: u32
    gl.GenTextures(1, &id)
    texture = id

    bind_texture_raw(texture_type, id)

    switch texture_type {
        case .TWO_DIM:
            gl.TexImage2D(gl.TEXTURE_2D, lod, internal_format, w, h, 0, format, type, data)
        case .CUBEMAP:
            for i in 0..<6 {
                gl.TexImage2D(u32(gl.TEXTURE_CUBE_MAP_POSITIVE_X + i), lod, internal_format, w, h, 0, format, type, data)
            }
        case .THREE_DIM: dbg.log(.ERROR, "Texture type not supported", loc=loc)
    }

    if len(texture_properties) == 0 {
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    }
    else do set_texture_properties(texture_type, texture_properties)

    generate_mipmap := generate_mipmap
    generate_mipmap |= texture_properties[.MIN_FILTER] == .LINEAR_MIPMAP_LINEAR
    generate_mipmap |= texture_properties[.MIN_FILTER] == .LINEAR_MIPMAP_NEAREST
    generate_mipmap |= texture_properties[.MIN_FILTER] == .NEAREST_MIPMAP_LINEAR
    generate_mipmap |= texture_properties[.MIN_FILTER] == .NEAREST_MIPMAP_NEAREST
    if generate_mipmap do gen_mipmap(texture_type)

    return
}

// Assumes bound texture at target type
gen_mipmap :: proc(texture_type: resource.TextureType) {
    gl.GenerateMipmap(conv_texture_type(texture_type))
}

@(private)
set_texture_properties :: proc(type: resource.TextureType, properties: resource.TextureProperties) {
    gl_type := conv_texture_type(type)
    for property, value in properties {
        gl.TexParameteri(gl_type, conv_tex_property(property), conv_tex_property_value(value))
    }
}

@(private)
conv_tex_property :: proc(property: resource.TextureProperty) -> u32 {
    switch property {
        case .WRAP_S: return gl.TEXTURE_WRAP_S
        case .WRAP_T: return gl.TEXTURE_WRAP_T
        case .WRAP_R: return gl.TEXTURE_WRAP_R
        case .MIN_FILTER: return gl.TEXTURE_MIN_FILTER
        case .MAG_FILTER: return gl.TEXTURE_MAG_FILTER
    }
    return 0
}

@(private)
conv_tex_property_value :: proc(val: resource.TexturePropertyValue) -> i32 {
    switch val {
        case .CLAMP_BORDER: return gl.CLAMP_TO_BORDER
        case .CLAMP_EDGE: return gl.CLAMP_TO_EDGE
        case .LINEAR: return gl.LINEAR
        case .LINEAR_MIPMAP_LINEAR: return gl.LINEAR_MIPMAP_LINEAR
        case .LINEAR_MIPMAP_NEAREST: return gl.LINEAR_MIPMAP_NEAREST
        case .MIRROR_CLAMP_EDGE: return gl.MIRROR_CLAMP_TO_EDGE
        case .MIRROR_REPEAT: return gl.MIRRORED_REPEAT
        case .NEAREST: return gl.NEAREST
        case .NEAREST_MIPMAP_LINEAR: return gl.NEAREST_MIPMAP_LINEAR
        case .NEAREST_MIPMAP_NEAREST: return gl.NEAREST_MIPMAP_NEAREST
        case .REPEAT: return gl.REPEAT
    }
    return 0
}


release_texture :: proc(texture: ^GPUTexture) {
    if id, id_ok := texture.?; id_ok do gl.DeleteTextures(1, &id)
}

bind_texture :: proc(#any_int texture_unit: u32, texture: GPUTexture, texture_type := resource.TextureType.TWO_DIM, loc := #caller_location) -> (ok: bool) {
    if texture == nil {
        dbg.log(dbg.LogLevel.ERROR, "Texture to bind at unit %d is not transferred to gpu", texture_unit, loc=loc)
        return
    }
    if texture_unit > 31 {
        dbg.log(dbg.LogLevel.ERROR, "Texture unit is greater than 31 - active textures limit exceeded")
        return
    }
    // dbg.log(.INFO, "Binding texture '%d' of type '%v' to unit '%d'", texture.?, texture_type, texture_unit, loc=loc)

    gl.ActiveTexture(u32(gl.TEXTURE0) + texture_unit)
    bind_texture_raw(texture_type, texture.?)
    return true
}

bind_texture_raw :: proc(texture_type: resource.TextureType, tid: u32) {
    gl.BindTexture(conv_texture_type(texture_type), tid)
}


conv_texture_type :: proc(type: resource.TextureType) -> u32 {
    switch type {
        case .TWO_DIM: return gl.TEXTURE_2D
        case .THREE_DIM: return gl.TEXTURE_3D
        case .CUBEMAP: return gl.TEXTURE_CUBE_MAP
    }
    return 0
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
        shader.id = compile_shader(shader) or_return
        shader_ids[i] = shader.id.?
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


attach_program :: proc(program: resource.ShaderProgram, loc := #caller_location) -> (ok: bool) {
    if program_id, id_ok := utils.unwrap_maybe(program.id); !id_ok {
        dbg.log(dbg.LogLevel.INFO, "Shader program not yet created")
        return
    }
    else{
        gl.UseProgram(program_id)
    }
    return true
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

set_blend :: proc(enable: bool) {
    if enable do gl.Enable(gl.BLEND)
    else do gl.Disable(gl.BLEND)
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
        case .FRONT_AND_BACK: return gl.FRONT_AND_BACK
    }
    return 0
}

@(private)
conv_face_culling  :: proc(face: FaceCulling) -> u32 {
    switch face {
        case .FRONT: return gl.FRONT
        case .BACK: return gl.BACK
        case .FRONT_AND_BACK: return gl.FRONT_AND_BACK
        case .ADAPTIVE: return 0
    }
    return 0
}

cull_geometry_faces :: proc(face: FaceCulling) {
    if face != .ADAPTIVE {
        gl.Enable(gl.CULL_FACE)
        gl.CullFace(conv_face_culling(face))
    }
}

set_face_culling :: proc(cull: bool) {
    if cull do gl.Enable(gl.CULL_FACE)
    else do gl.Disable(gl.CULL_FACE)
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


// Framebuffers

gen_framebuffer :: proc() -> (id: u32) {
    gl.GenFramebuffers(1, &id)
    return
}

@(private)
bind_framebuffer_raw :: proc(fbo: u32) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
}

bind_framebuffer :: proc(frame_buffer: FrameBuffer, loc := #caller_location) -> (ok: bool) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, utils.unwrap_maybe(frame_buffer.id, loc) or_return)
    return true
}

bind_default_framebuffer :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

release_framebuffer :: proc(frame_buffer: FrameBuffer, loc := #caller_location) -> (ok: bool) {
    frame_buffer := frame_buffer
    gl.DeleteFramebuffers(1, utils.unwrap_maybe_ptr(&frame_buffer.id, loc) or_return)
    return true
}

check_framebuffer_status :: proc(framebuffer: FrameBuffer, log := true, loc := #caller_location) -> (ok: bool) {
    bind_framebuffer(framebuffer) or_return
    return check_framebuffer_status_raw(log, loc)
}

check_framebuffer_status_raw :: proc(log := true, loc := #caller_location) -> (ok: bool) {
    ok = gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE
    if !ok && log do dbg.log(.ERROR, "Framebuffer status is invalid/incomplete")
    return
}

gen_renderbuffer :: proc() -> (id: u32) {
    gl.GenRenderbuffers(1, &id)
    return
}

bind_renderbuffer :: proc(render_buffer: RenderBuffer, loc := #caller_location) -> (ok: bool) {
    gl.BindRenderbuffer(gl.RENDERBUFFER, utils.unwrap_maybe(render_buffer.id, loc) or_return)
    return true
}

bind_renderbuffer_raw :: proc(rbo: u32) {
    gl.BindRenderbuffer(gl.RENDERBUFFER, rbo)
}

set_render_buffer_storage :: proc(internal_format: u32 = gl.RGBA, w, h: i32) {
    gl.RenderbufferStorage(gl.RENDERBUFFER, internal_format, w, h)
}

make_renderbuffer :: proc(w, h: i32, internal_format: u32 = gl.RGBA) -> (render_buffer: RenderBuffer) {
    render_buffer.id = gen_renderbuffer()
    bind_renderbuffer(render_buffer)
    set_render_buffer_storage(internal_format, w, h)
    return
}

// Assumes bound fbo
bind_texture_to_frame_buffer :: proc(
    fbo: u32,
    texture: resource.Texture,
    type: AttachmentType,
    cube_face: u32 = 0,
    attachment_loc: u32 = 0,
    mip_level: i32 = 0,
    loc := #caller_location
) -> (ok: bool) {
    dbg.log()
    tid := utils.unwrap_maybe(texture.gpu_texture, loc) or_return

    gl_attachment_id: u32 = 0
    switch type {
        case .COLOUR: gl_attachment_id = gl.COLOR_ATTACHMENT0 + attachment_loc
        case .DEPTH: gl_attachment_id = gl.DEPTH_ATTACHMENT
        case .STENCIL: gl_attachment_id = gl.STENCIL_ATTACHMENT
        case .DEPTH_STENCIL: gl_attachment_id = gl.DEPTH_STENCIL_ATTACHMENT
    }

    if texture.type == .CUBEMAP {
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl_attachment_id, gl.TEXTURE_CUBE_MAP_POSITIVE_X + cube_face, tid, mip_level)
    }
    else {
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl_attachment_id, conv_texture_type(texture.type), tid, mip_level)
    }

    return true
}

detach_from_framebuffer :: proc(fbo: u32, texture_type: resource.TextureType, type: AttachmentType, cube_face: u32 = 0, attachment_loc: u32 = 0) {
    dbg.log()

    gl_attachment_id: u32 = 0
        switch type {
        case .COLOUR: gl_attachment_id = gl.COLOR_ATTACHMENT0 + attachment_loc
        case .DEPTH: gl_attachment_id = gl.DEPTH_ATTACHMENT
        case .STENCIL: gl_attachment_id = gl.STENCIL_ATTACHMENT
        case .DEPTH_STENCIL: gl_attachment_id = gl.DEPTH_STENCIL_ATTACHMENT
    }

    if texture_type == .CUBEMAP {
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl_attachment_id, gl.TEXTURE_CUBE_MAP_POSITIVE_X + cube_face, 0, 0)
    }
    else {
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl_attachment_id, conv_texture_type(texture_type), 0, 0)
    }
}

bind_renderbuffer_to_frame_buffer :: proc(
    fbo: u32,
    render_buffer: RenderBuffer,
    type: AttachmentType,
    attachment_loc: u32 = 0,
    loc := #caller_location
) -> (ok: bool) {
    rbo := utils.unwrap_maybe(render_buffer.id, loc) or_return
    bind_framebuffer_raw(fbo)

    gl_attachment_id: u32 = 0
    switch type {
        case .COLOUR: gl_attachment_id = gl.COLOR_ATTACHMENT0 + attachment_loc
        case .DEPTH: gl_attachment_id = gl.DEPTH_ATTACHMENT
        case .STENCIL: gl_attachment_id = gl.STENCIL_ATTACHMENT
        case .DEPTH_STENCIL: gl_attachment_id = gl.DEPTH_STENCIL_ATTACHMENT
    }

    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl_attachment_id, gl.RENDERBUFFER, rbo)

    return true
}


set_render_viewport :: proc(x_start, y_start, w, h: i32) {
    gl.Viewport(x_start, y_start, w, h)
}

ClearProperty :: enum {
    COLOUR_BIT,
    DEPTH_BIT,
    STENCIL_BIT
}

ClearMask :: bit_set[ClearProperty]
clear_mask :: proc(mask: ClearMask) {
    gl_mask: u32 = 0
    for prop in mask {
        gl_prop: u32
        switch prop {
            case .COLOUR_BIT: gl_prop = gl.COLOR_BUFFER_BIT
            case .DEPTH_BIT: gl_prop = gl.DEPTH_BUFFER_BIT
            case .STENCIL_BIT: gl_prop = gl.STENCIL_BUFFER_BIT
        }
        gl_mask |= gl_prop
    }
    if gl_mask != 0 do gl.Clear(gl_mask)
}

set_multisampling :: proc(on: bool) {
    if on do gl.Enable(gl.MULTISAMPLE)
    else do gl.Disable(gl.MULTISAMPLE)
}

set_clear_colour :: proc(colour: [4]f32 = {}) {
    gl.ClearColor(colour.x, colour.y, colour.z, colour.a)
}

set_depth_func :: proc(func: DepthFunc) {
    gl.DepthFunc(conv_depth_func(func))
}

conv_depth_func :: proc(func: DepthFunc) -> u32 {
    switch func {
        case .LESS: return gl.LESS
        case .NEVER: return gl.NEVER
        case .EQUAL: return gl.EQUAL
        case .LEQUAL: return gl.LEQUAL
        case .GREATER: return gl.GREATER
        case .GEQUAL: return gl.GEQUAL
        case .NOTEQUAL: return gl.NOTEQUAL
        case .ALWAYS: return gl.ALWAYS
    }
    return 0
}

set_default_depth_func :: proc() {
    gl.DepthFunc(gl.LESS)
}