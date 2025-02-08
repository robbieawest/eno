package render

import gl "vendor:OpenGL"

import dbg "../debug"

import "core:reflect"
import "core:strings"


Pipeline :: struct {
    passes: [dynamic]RenderPass
}

RenderPass :: struct {
    frame_buffer: FrameBuffer
}


FrameBuffer :: struct {
    id: Maybe(u32),
    w, h: u32,
    attachments: [dynamic]FrameBufferAttachment
}


AttachmentType :: enum {
    COLOUR,
    DEPTH,
    STENCIL,
    DEPTH_STENCIL
}

FrameBufferAttachment :: struct {
    type: AttachmentType,
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
    gen_framebuffer
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

// !!!
// todo if last render pass has an attached renderbuffer, then blit that renderbuffer to final frame
// if its not a renderbuffer but a texture buffer then just render that texture onto a single quad

make_attachment :: proc(frame_buffer: ^FrameBuffer, type: AttachmentType, internal_backing_type: i32 = gl.RGBA, backing_type: u32 = gl.FLOAT, lod: i32 = 0) {
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

    texture := make_texture(internal_type = internal_backing_type, w = frame_buffer.w, h = frame_buffer.h, type = backing_type, lod = lod)
    gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

    attatchment_id := 0
    switch type {
        case .COLOUR: attatchment_id = gl.COLOR_ATTACHMENT0 + n_attachments
        case .DEPTH: attatchment_id = gl.DEPTH_ATTACHMENT
        case .STENCIL: attatchment_id = gl.STENCIL_ATTACHMENT
        case .DEPTH_STENCIL: attatchment_id = gl.DEPTH_STENCIL_ATTACHMENT
    }
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, attachment_id, gl.TEXTURE_2D, texture.id, lod)

    append(&frame_buffer.texture_attachments, texture)
}

@(private)
get_n_attachments :: proc(frame_buffer: ^FrameBuffer,  type: AttachmentType) -> (n: int) {
    for attachment in frame_buffer.texture_attachments do n += int(attachment.type == type)
}