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

make_renderbuffer :: proc() -> (render_buffer: RenderBuffer) {
    // todo
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

    }
    else {
        attachment.data = make_texture(internal_type = internal_backing_type, w = frame_buffer.w, h = frame_buffer.h, type = backing_type, lod = lod)
        gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
        gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

        gl.FramebufferTexture2D(gl.FRAMEBUFFER, attachment_id, gl.TEXTURE_2D, attachment.data.id, lod)
    }

    append(&frame_buffer.attachments, attachment)
}

@(private)
get_n_attachments :: proc(frame_buffer: ^FrameBuffer,  type: AttachmentType) -> (n: int) {
    for attachment in frame_buffer.texture_attachments do n += int(attachment.type == type)
}