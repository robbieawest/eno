package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../shader"

import "core:reflect"
import "core:strings"
import "../utils"


RenderPipeline :: struct {
    passes: [dynamic]RenderPass
}

destroy_pipeline :: proc(pipeline: ^RenderPipeline) {
    for &pass in passes do destroy_render_pass(pass)
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
    w, h: u32,
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

generate_framebuffer :: proc(w, h: u32) -> (frame_buffer: FrameBuffer, ok: bool) {
    frame_buffer.w = w
    frame_buffer.h = h
    gen_framebuffer(&frame_buffer.id)
    ok = gl.CheckFramebufferStatus(frame_buffer.id.?) == gl.FRAMEBUFFER_COMPLETE
    frame_buffer.texture_attachments = make([dynamic]TextureAttachment)
}

destroy_framebuffer :: proc(frame_buffer: ^FrameBuffer) {
    delete(frame_buffer.texture_attachments)
    if frame_buffer.id != nil do gl.DeleteFramebuffers(1, frame_buffer.id.?)
}


@(private)
gen_framebuffer :: proc(id: ^u32)  {
    gl.GenFramebuffers(1, &id)
}

bind_framebuffer :: proc(frame_buffer: ^FrameBuffer) {
    if frame_buffer.id == nil do gen_framebuffer(&frame_buffer.id)
    gl.BindFramebuffer(gl.FRAMEBUFFEr, frame_buffer.id.?)
}

bind_default_framebuffer :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}


gen_renderbuffer :: proc(id: ^u32) {
    gl.GenRenderbuffers(1, &id)
}

bind_renderbuffer :: proc(render_buffer: ^RenderBuffer) {
    if render_buffer.id == nil do gen_renderbuffer(&render_buffer.id)
    gl.BindRenderbuffer(gl.RENDERBUFFER, render_buffer.id.?)
}

make_renderbuffer :: proc(w, h: i32, internal_format := gl.RGBA) -> (render_buffer: RenderBuffer) {
    gen_renderbuffer(&render_buffer.id)
    bind_renderbuffer(&render_buffer)
    gl.RenderbufferStorage(gl.RENDERBUFFER, internal_format, w, h)
}


/*
    "Draws" framebuffer at the attachment, render mask, interpolation, and w, h to the default framebuffer (sdl back buffer)
*/
draw_framebuffer_to_screen :: proc(frame_buffer: ^FrameBuffer, attachment_index: int, w, h: i32, render_mask: RenderMask = ColourMask, interpolation := gl.NEAREST) {
    if frame_buffer.id == nil {
        dbg.debug_point(dbg.LogLevel.ERROR, "Frame buffer not yet created")
        return
    }
    if attachment_index >= len(frame_buffer.attachments) {
        dbg.debug_point(dbg.LogLevel, "Attachment index: %d out of range for attachments length %d", attachment_index, len(frame_buffer.attachments))
        return
    }

    attachment := &frame_buffer.attachments[attachment_index]

    switch data in AttachmentData {
        case RenderBuffer:
            gl.BindFramebuffer(gl.READ_FRAMEBUFFER, frame_buffer.id.?)
            gl.ReadBuffer(attachment.id)  // Id not validated
            gl.BindFrameBuffer(gl.DRAW_FRAMEBUFFER, 0)
            gl.BlitFramebuffer(0, 0, w, h, 0, 0, w, h, render_mask, interpolation)
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
make_attachment :: proc(frame_buffer: ^FrameBuffer, type: AttachmentType, internal_backing_type: i32 = gl.RGBA, backing_type: u32 = gl.FLOAT, lod: i32 = 0, is_renderbuffer := false) {
    n_attachments := get_n_attachments(frame_buffer, type)
    if type != .COLOR && n_attachments >= 1 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Number of %s texture attachments exceeds 0", strings.to_lower(reflect.enum_name_from_value(type)))
        return
    }
    else if n_attachments >= gl.MAX_COLOR_ATTACHMENTS {
        dbg.debug_point(dbg.LogLevel.ERROR, "Number of colour texture attachments exceeds max: %d", gl.MAX_COLOR_ATTACHMENTS)
        return
    }

    bind_framebuffer(frame_buffer)
    defer bind_default_framebuffer()


    gl_attachment_id := 0
    switch type {
        case .COLOUR: gl_attachment_id = gl.COLOR_ATTACHMENT0 + n_attachments
        case .DEPTH: gl_attachment_id = gl.DEPTH_ATTACHMENT
        case .STENCIL: gl_attachment_id = gl.STENCIL_ATTACHMENT
        case .DEPTH_STENCIL: gl_attachment_id = gl.DEPTH_STENCIL_ATTACHMENT
    }

    attachment := Attachment { id = gl_attachment_id, type = type }

    if is_renderbuffer {
        render_buffer = make_renderbuffer(frame_buffer.w, frame_buffer.h, internal_backing_type)

        frame_buffer_id, fid_ok := utils.unwrap_maybe(frame_buffer.id)
        render_buffer_id, rid_ok := utils.unwrap_maybe(render_buffer.id)
        if fid_ok && rid_ok {
            gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, utils.unwrap_maybe(frame_buffer.id), gl_attachment_id, gl.RENDERBUFFER, utils.unwrap_maybe(render_buffer.id))
        }
        attachment.data = render_buffer
    }
    else {
        texture = make_texture(internal_type = internal_backing_type, w = frame_buffer.w, h = frame_buffer.h, type = backing_type, lod = lod)
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
get_n_attachments :: proc(frame_buffer: ^FrameBuffer,  type: AttachmentType) -> (n: int) {
    for attachment in frame_buffer.texture_attachments do n += int(attachment.type == type)
}