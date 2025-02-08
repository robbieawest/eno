package render

import gl "vendor:OpenGL"

import dbg "../debug"


Pipeline :: struct {
    passes: ^RenderPass
}

RenderPass :: struct {
    frame_buffer: FrameBuffer
}

FrameBuffer :: struct {
    id: Maybe(u32),
    w, h: u32,
    texture_attachments: [dynamic]TextureAttachment
}


AttachmentType :: enum {
    COLOUR,
    DEPTH,
    STENCIL,
    DEPTH_STENCIL
}

TextureAttachment :: struct {
    type: AttachmentType,
    texture: Texture
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
    if frame_buffer.id == nil do gen_framebuffer(frame_buffer.id)
    gl.BindFramebuffer(gl.FRAMEBUFFEr, frame_buffer.id.?)
}


bind_default_framebuffer :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

// !!!
// todo if last render pass has an attached renderbuffer, then blit that renderbuffer to final frame
// if its not a renderbuffer but a texture buffer then just render that texture onto a single quad

attach_colour_texture :: proc(frame_buffer: ^FrameBuffer, internal_backing_type: i32 = gl.RGBA, backing_type: u32 = gl.FLOAT, lod: i32 = 0) {
    n_colour_attachments := get_n_colour_attachments(frame_buffer)
    if n_colour_attachments >= gl.MAX_COLOR_ATTACHMENTS {
        dbg.debug_point(dbg.LogLevel.ERROR, "Number of colour texture attachments exceeds max: %d", gl.MAX_COLOR_ATTACHMENTS)
    }

    bind_framebuffer(frame_buffer)
    defer bind_default_framebuffer()

    texture := make_texture(internal_type = internal_backing_type, w = frame_buffer.w, h = frame_buffer.h, type = backing_type, lod = lod)
    gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0 + n_colour_attachments, gl.TEXTURE_2D, texture.id, lod)

    append(&frame_buffer.texture_attachments, texture)
}

@(private)
get_n_colour_attachments :: proc(frame_buffer: ^FrameBuffer) -> (n: int) {
    for attachment in frame_buffer.texture_attachments do n += int(attachment.type == .COLOUR)
}