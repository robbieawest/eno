package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../shader"
import "../utils"

import "core:reflect"
import "core:strings"
import "core:slice"
import "core:math"
import "base:intrinsics"

RenderPipeline :: struct {
    passes: [dynamic]RenderPass
}

destroy_pipeline :: proc(pipeline: ^RenderPipeline) {
    for &pass in pipeline.passes do destroy_render_pass(&pass)
    delete(pipeline.passes)
}

RenderPass :: struct {
    frame_buffer: FrameBuffer
}

destroy_render_pass :: proc(render_pass: ^RenderPass) {
    destroy_framebuffer(&render_pass.frame_buffer)
}


ShaderPassInfo :: enum u32 {
    PBR,
    DIRECT,
    CUSTOM,
}
ShaderPassInfos :: bit_set[ShaderPassInfo]

DrawInfo :: enum {
    DRAW_ALL,
    DRAW_TRANSPARENT_MODELS,  // Only draw models selected to be transparent
}

PassInfo :: struct {
    attachments_info: []AttachmentInfo,
    shader_info: ShaderPassInfos
}

/*
    Give 0 for backing_type, lod and internal_backing_type if these are not important to you.
    Clones given attachments - remember to call destroy_pass_info
*/
make_pass_info :: proc(shader_info: ShaderPassInfos, attachments: ..AttachmentInfo) -> PassInfo {
    return PassInfo{ slice.clone(attachments), shader_info }
}

destroy_pass_info :: proc(pass_info: ^PassInfo) {
    delete(pass_info.attachments_info)
}


BufferType :: enum {
    TEXTURE,
    RENDER
}
AttachmentInfo :: struct {
    type: AttachmentType,
    buffer_type: BufferType,
    backing_type: u32,
    lod: i32,
    internal_backing_type: u32
}


FrameBuffer :: struct {
    id: Maybe(u32),
    w, h: i32,
    attachments: [dynamic]Attachment
}


AttachmentType :: enum {
    COLOUR,
    DEPTH,
    STENCIL,
    DEPTH_STENCIL
}

Attachment :: struct {
    type: AttachmentType,
    id: u32,  // Attachment id (GL_COLOR_ATTACHMENT0 for example)
    data: AttachmentData
}

AttachmentData :: union {
    Texture,
    RenderBuffer
}

RenderBuffer :: struct {
    id: Maybe(u32)
}

generate_framebuffer :: proc(w, h: i32) -> (frame_buffer: FrameBuffer, ok: bool) {
    frame_buffer.w = w
    frame_buffer.h = h

    id: u32
    gen_framebuffer(&id)
    frame_buffer.id = id

    ok = gl.CheckFramebufferStatus(id) == gl.FRAMEBUFFER_COMPLETE
    frame_buffer.attachments = make([dynamic]Attachment)
    return
}

destroy_framebuffer :: proc(frame_buffer: ^FrameBuffer) {
    delete(frame_buffer.attachments) // todo delete more
    if id, id_ok := frame_buffer.id.?; id_ok do gl.DeleteFramebuffers(1, &id)
}


@(private)
gen_framebuffer :: proc(id: ^u32)  {
    gl.GenFramebuffers(1, id)
}

bind_framebuffer :: proc(frame_buffer: ^FrameBuffer) {
    id, id_ok := frame_buffer.id.?
    if !id_ok do gen_framebuffer(&id)
    gl.BindFramebuffer(gl.FRAMEBUFFER, id)
}

bind_default_framebuffer :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}


gen_renderbuffer :: proc(id: ^u32) {
    gl.GenRenderbuffers(1, id)
}

bind_renderbuffer :: proc(render_buffer: ^RenderBuffer) {
    id, id_ok := render_buffer.id.?
    if !id_ok do gen_renderbuffer(&id)
    gl.BindRenderbuffer(gl.RENDERBUFFER, id)
}

make_renderbuffer :: proc(w, h: i32, internal_format: u32 = gl.RGBA) -> (render_buffer: RenderBuffer) {
    id: u32
    gen_renderbuffer(&id)
    render_buffer.id = id
    bind_renderbuffer(&render_buffer)
    gl.RenderbufferStorage(gl.RENDERBUFFER, internal_format, w, h)
    return
}


RenderType :: enum {
    COLOUR = intrinsics.constant_log2(gl.COLOR_BUFFER_BIT),
    DEPTH = intrinsics.constant_log2(gl.DEPTH_BUFFER_BIT),
    STENCIL = intrinsics.constant_log2(gl.STENCIL_BUFFER_BIT)
}

RenderMask :: bit_set[RenderType; u32]

render_mask_to_gl_buffer_mask :: proc(type: RenderMask) -> u32 {
    return u32(math.pow_f32(2, cast(f32)(transmute(u32)type)))
}

ColourMask :: RenderMask{ .COLOUR }
DepthMask :: RenderMask{ .DEPTH }
StencilMask :: RenderMask{ .STENCIL }

/*
    "Draws" framebuffer at the attachment, render mask, interpolation, and w, h to the default framebuffer (sdl back buffer)
*/
draw_framebuffer_to_screen :: proc(frame_buffer: ^FrameBuffer, attachment_index: int, w, h: i32, render_mask: RenderMask = ColourMask, interpolation: u32 = gl.NEAREST) {
    frame_buffer_id, id_ok := frame_buffer.id.?
    if !id_ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "Frame buffer not yet created")
        return
    }
    if attachment_index >= len(frame_buffer.attachments) {
        dbg.debug_point(dbg.LogLevel.ERROR, "Attachment index: %d out of range for attachments length %d", attachment_index, len(frame_buffer.attachments))
        return
    }

    attachment := &frame_buffer.attachments[attachment_index]

    switch data in attachment.data {
        case RenderBuffer:
            gl.BindFramebuffer(gl.READ_FRAMEBUFFER, frame_buffer_id)
            gl.ReadBuffer(attachment.id)  // Id not validated
            gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
            gl.BlitFramebuffer(0, 0, w, h, 0, 0, w, h, transmute(u32)render_mask, interpolation) // todo figure this out
        case Texture:
            // todo
    }
}


// !!! (draw_framebuffer_to_screen)
// todo if last render pass has an attached renderbuffer, then blit that renderbuffer to final frame
// if its not a renderbuffer but a texture buffer then just render that texture onto a single quad

/*
    Creates an attachment of type, either a renderbuffer or a texture.
    The internal backing type gives the type to be used to store individual data points in the attachment.
    backing_type and lod are both only used for texture output (if is_render_buffer is not set to true).
*/
make_attachment :: proc(
    frame_buffer: ^FrameBuffer,
    type: AttachmentType,
    internal_backing_type: u32 = gl.RGBA,
    backing_type: u32 = gl.FLOAT,
    lod: i32 = 0,
    is_renderbuffer := false
) -> (ok: bool) {
    n_attachments := get_n_attachments(frame_buffer, type)
    if type != .COLOUR && n_attachments >= 1 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Number of %s texture attachments exceeds 0", strings.to_lower(reflect.enum_name_from_value(type) or_return))
        return
    }
    else if n_attachments >= gl.MAX_COLOR_ATTACHMENTS {
        dbg.debug_point(dbg.LogLevel.ERROR, "Number of colour texture attachments exceeds max: %d", gl.MAX_COLOR_ATTACHMENTS)
        return
    }

    bind_framebuffer(frame_buffer)
    defer bind_default_framebuffer()


    gl_attachment_id: u32 = 0
    switch type {
        case .COLOUR: gl_attachment_id = gl.COLOR_ATTACHMENT0 + n_attachments
        case .DEPTH: gl_attachment_id = gl.DEPTH_ATTACHMENT
        case .STENCIL: gl_attachment_id = gl.STENCIL_ATTACHMENT
        case .DEPTH_STENCIL: gl_attachment_id = gl.DEPTH_STENCIL_ATTACHMENT
    }

    attachment := Attachment { id = gl_attachment_id, type = type }

    if is_renderbuffer {
        render_buffer := make_renderbuffer(frame_buffer.w, frame_buffer.h, internal_backing_type)

        frame_buffer_id, fid_ok := utils.unwrap_maybe(frame_buffer.id)
        render_buffer_id, rid_ok := utils.unwrap_maybe(render_buffer.id)
        if fid_ok && rid_ok {
            gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, utils.unwrap_maybe(frame_buffer.id) or_return, gl_attachment_id, gl.RENDERBUFFER, utils.unwrap_maybe(render_buffer.id) or_return)
        }
        attachment.data = render_buffer
    }
    else { // todo fix backing types
        texture := make_texture(internal_type = internal_backing_type, w = frame_buffer.w, h = frame_buffer.h, type = backing_type, lod = lod)
        gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
        gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

        if texture_id, id_ok := utils.unwrap_maybe; id_ok {
            gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl_attachment_id, gl.TEXTURE_2D, utils.unwrap_maybe(texture.id), lod)
        }
        attachment.data = texture
    }

    append(&frame_buffer.attachments, attachment)
}

@(private)
get_n_attachments :: proc(frame_buffer: ^FrameBuffer,  type: AttachmentType) -> (n: u32) {
    for attachment in frame_buffer.attachments do n += u32(attachment.type == type)
    return
}