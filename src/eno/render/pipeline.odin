package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../utils"
import mutils "../utils/math_utils"

import "core:reflect"
import "core:strings"
import "base:intrinsics"


RenderPipeline :: struct {
    passes: [dynamic]RenderPass
}

// Default render pipeline has no passes
make_render_pipeline :: proc(passes: ..RenderPass) -> (ret: RenderPipeline) {
    ret.passes = make([dynamic]RenderPass, 0, len(passes))
    append_elems(&ret.passes, ..passes)
    return
}

destroy_pipeline :: proc(pipeline: ^RenderPipeline) {
    for &pass in pipeline.passes do destroy_render_pass(&pass)
    delete(pipeline.passes)
}


RenderPassType :: enum {
    LIGHTING,
    POST
}

// Structure may be too simple
RenderPass :: struct {
    frame_buffer: FrameBuffer,
    type: RenderPassType
}

// Populate this when needed
make_render_pass :: proc(frame_buffer: FrameBuffer) -> RenderPass {
    return { frame_buffer , .LIGHTING }
}

destroy_render_pass :: proc(render_pass: ^RenderPass) {
    destroy_framebuffer(&render_pass.frame_buffer)
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

// Todo make sure inner framebuffers only use textures
FrameBuffer :: struct {
    id: Maybe(u32),
    w, h: i32,
    attachments: map[u32]Attachment
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

destroy_attachment :: proc(attachment: ^Attachment) {
    switch &data in attachment.data {
        case GPUTexture: release_texture(&data)
        case RenderBuffer: release_render_buffer(&data)
    }
}


AttachmentData :: union {
    GPUTexture,
    RenderBuffer
}

RenderBuffer :: struct {
    id: Maybe(u32)
}

release_render_buffer :: proc(render_buffer: ^RenderBuffer) {
    if id, id_ok := render_buffer.id.?; id_ok do gl.DeleteRenderbuffers(1, &id)
}


generate_framebuffer :: proc(w, h: i32) -> (frame_buffer: FrameBuffer, ok: bool) {
    frame_buffer.w = w
    frame_buffer.h = h

    id: u32
    gen_framebuffer(&id)
    frame_buffer.id = id

    ok = gl.CheckFramebufferStatus(id) == gl.FRAMEBUFFER_COMPLETE
    frame_buffer.attachments = make(map[u32]Attachment)
    return
}

destroy_framebuffer :: proc(frame_buffer: ^FrameBuffer) {
    for _, &attachment in frame_buffer.attachments do destroy_attachment(&attachment)
    delete(frame_buffer.attachments)
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

render_mask_to_gl_buffer_mask :: proc(type: RenderMask) -> (mask: u32) {
    return mutils.pow_u32(2, transmute(u32)type)
    //return u32(math.pow_f32(2, cast(f32)(transmute(u32)type)))
}

ColourMask :: RenderMask{ .COLOUR }
DepthMask :: RenderMask{ .DEPTH }
StencilMask :: RenderMask{ .STENCIL }

/*
    "Draws" framebuffer at the attachment, render mask, interpolation, and w, h to the default framebuffer (sdl back buffer)
*/
draw_framebuffer_to_screen :: proc(frame_buffer: ^FrameBuffer, attachment_id: u32, w, h: i32, interpolation: u32 = gl.NEAREST) {
    frame_buffer_id, id_ok := frame_buffer.id.?
    if !id_ok {
        dbg.log(.ERROR, "Frame buffer not yet created")
        return
    }

    attachment, attachment_ok := &frame_buffer.attachments[attachment_id]
    if !attachment_ok {
        dbg.log(.ERROR, "Attachment ID: %d is invalid or not bound to the framebuffer", attachment_id)
        return
    }

    switch data in attachment.data {
        case RenderBuffer:
            gl.BindFramebuffer(gl.READ_FRAMEBUFFER, frame_buffer_id)
            gl.ReadBuffer(attachment.id)  // Id not validated
            gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)

            gl.BlitFramebuffer(0, 0, w, h, 0, 0, w, h,  gl.COLOR_ATTACHMENT0, interpolation)  // This could be smarter
        case GPUTexture:
            // todo
    }
}


// !!! (draw_framebuffer_to_screen)
// todo if last render pass has an attached renderbuffer, then blit that renderbuffer to final frame
// if its not a renderbuffer but a texture buffer then just render that texture onto a single quad

/*
    Creates an attachment of type, either a renderbuffer or a texture.
    is_render_buffer specifies whether the attachment is renderbuffer or texture

    texture_internal_format and texture_backing_type are only used in the texture case
*/
make_attachment :: proc(
    frame_buffer: ^FrameBuffer,
    type: AttachmentType,
    texture_internal_format: i32 = gl.RGBA,
    texture_backing_type: u32 = gl.FLOAT,
    format: u32 = gl.RGBA,
    lod: i32 = 0,
    is_render_buffer := false
) -> (ok: bool) {
    n_attachments := get_n_attachments(frame_buffer, type)
    if type != .COLOUR && n_attachments >= 1 {
        dbg.log(.ERROR, "Number of %s texture attachments exceeds 0", strings.to_lower(reflect.enum_name_from_value(type) or_return))
        return
    }
    else if n_attachments >= gl.MAX_COLOR_ATTACHMENTS {
        dbg.log(.ERROR, "Number of colour texture attachments exceeds max: %d", gl.MAX_COLOR_ATTACHMENTS)
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

    if is_render_buffer {
        render_buffer := make_renderbuffer(frame_buffer.w, frame_buffer.h, format)

        gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl_attachment_id, gl.RENDERBUFFER, render_buffer.id.? or_return)
        attachment.data = render_buffer
    }
    else {
        texture := make_texture(frame_buffer.w, frame_buffer.h, internal_format=texture_internal_format, format=format, type=texture_backing_type, lod = lod)
        if texture == nil {
            dbg.log(.ERROR, "make texture returned a nil texture")
            return
        }

        gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
        gl.TexParameteri(gl.FRAMEBUFFER, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl_attachment_id, gl.TEXTURE_2D, texture.?, lod)
        attachment.data = texture
    }

    frame_buffer.attachments[gl_attachment_id] = attachment
    ok = true
    return
}

@(private)
get_n_attachments :: proc(frame_buffer: ^FrameBuffer,  type: AttachmentType) -> (n: u32) {
    for _, attachment in frame_buffer.attachments do n += u32(attachment.type == type)
    return
}