package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../utils"
import mutils "../utils/math_utils"
import "../ecs"

import "core:reflect"
import "core:strings"
import "base:intrinsics"

FrameBufferID :: u32  // Index into RenderPipeline.frame_buffers - checked
RenderPipeline :: struct($N_bufs: int) {
    frame_buffers: [N_bufs]FrameBuffer,
    passes: [dynamic]RenderPass
}

// Default render pipeline has no passes
init_render_pipeline :: proc{ init_render_pipeline_no_bufs, init_render_pipeline_bufs }

// Default render pipeline has no passes
init_render_pipeline_no_bufs :: proc(allocator := context.allocator) -> (ret: RenderPipeline(0)) {
    ret.passes = make([dynamic]RenderPass, allocator=allocator)
    return
}

// Default render pipeline has no passes
init_render_pipeline_bufs :: proc(buffers: [$N]FrameBuffer, allocator := context.allocator) -> (ret: RenderPipeline(N)) {
    ret.frame_buffers = buffers
    ret.passes = make([dynamic]RenderPass, allocator=allocator)
    return
}

add_render_passes :: proc(pipeline: ^RenderPipeline($N), passes: ..RenderPass) -> (ok: bool) {
    for pass in passes {
        if pass.frame_buffer != nil && int(pass.frame_buffer.?) >= N {
            dbg.log(.ERROR, "Render pass framebuffer id '%d' does not correspond to a framebuffer in the pipeline", pass.frame_buffer)
            return
        }

        append(&pipeline.passes, pass)
    }

    return true
}



// Releases GPU memory
destroy_pipeline :: proc(pipeline: ^RenderPipeline) {
    for &fbo in pipeline.frame_buffers do destroy_framebuffer(&fbo)
    delete(pipeline.passes)
}



GeometryZSort :: enum u8 {
    NO_SORT,
    ASC,
    DESC,
}

RenderMask :: enum u8 {
    DISABLE_COL_R,
    DISABLE_COL_G,
    DISABLE_COL_B,
    DISABLE_COL_A,
    DISABLE_DEPTH,
    ENABLE_STENCIL
}

disable_colour :: proc() -> bit_set[RenderMask; u8] {
    return { .DISABLE_COL_R, .DISABLE_COL_G, .DISABLE_COL_B, .DISABLE_COL_A }
}

WriteFunc :: enum u8 {
    NEVER,
    LESS,
    EQUAL,
    LEQUAL,
    GREATER,
    NOTEQUAL,
    GEQUAL,
    ALWAYS
}

Face :: enum u8 {
    FRONT,
    BACK,
    FRONT_AND_BACk
}

PolygonDisplayMode :: enum u8 {
    FILL,
    POINT,
    LINE
}

PolygonMode :: struct {
    face: Face,
    display_mode: PolygonDisplayMode
}

BlendParameter :: enum u8 {
    ZERO,
    ONE,
    SOURCE,
    ONE_MINUS_SOURCE,
    DEST,
    ONE_MINUS_DEST,
    SOURCE_ALPHA,
    ONE_MINUS_SOURCE_ALPHA,
    DEST_ALPHA,
    ONE_MINUS_DEST_ALPHA,
    CONSTANT_COLOUR,
    ONE_MINUS_CONSTANT_COLOUR,
    CONSTANT_ALPHA,
    ONE_MINUS_CONSTANT_ALPHA,
    ALPHA_SATURATE,
}

BlendFunc :: struct {
    source: BlendParameter,
    dest: BlendParameter
}

FrontFaceMode :: enum u8 {
    COUNTER_CLOCKWISE,
    CLOCKWISE,
}

RenderPassProperties :: struct {
    geometry_z_sorting: GeometryZSort,
    masks: bit_set[RenderMask; u8],
    blend_func: Maybe(BlendFunc),
    polygon_mode: Maybe(PolygonMode),
    front_face: FrontFaceMode,
    face_culling: Maybe(Face),
    disable_depth_test: bool,
    stencil_test: bool,
}


/*
    Creator is responsible for cleaning render pass queries
    These strings are component queries with action of QUERY_NO_INCLUDE
    Meaning you can query that a component must exist, and that it's data must match (provide nil for data rawptr to query by component availability)
    The label must not be of WORLD_COMPONENT, MODEL_COMPONENT or VISIBLE_COMPONENT
*/
RenderPassQuery :: []struct{ label: string, data: rawptr }

RenderPassMeshGather :: union { RenderPassQuery, ^RenderPass }

// Structure may be too simple
RenderPass :: struct {
    frame_buffer: Maybe(FrameBufferID),
    // If ^RenderPass, use the mesh data queried in that render pass
    // When constructing a render pass, if mesh_gather : ^RenderPass then it will follow back through the references to find a RenderPassQuery
    mesh_gather: RenderPassMeshGather,
    properties: RenderPassProperties
}




// Populate this when needed
make_render_pass:: proc(n_frame_buffers: $N, frame_buffer: Maybe(FrameBufferID), mesh_gather: RenderPassMeshGather, properties: RenderPassProperties = {}) -> (pass: RenderPass, ok: bool) {
    if frame_buffer != nil && frame_buffer.? >= n_frame_buffers {
        dbg.log(.ERROR, "Frame buffer points outside of the number of frame buffers")
        return
    }
    pass.frame_buffer = frame_buffer
    pass.mesh_gather = mesh_gather
    pass.properties = properties

    if !check_render_pass_gather(pass, 0, n_frame_buffers) {
        dbg.log(.ERROR, "Render pass mesh gather must end in an ecs.SceneQuery")
        return
    }

    ok = true
    return
}

@(private)
check_render_pass_gather :: proc(pass: ^RenderPass, iteration_curr: int, iteration_limit: int) -> (ok: bool) {
    if iteration_curr == iteration_limit do return false
    switch v in pass.mesh_gather {
        case RenderPassQuery: return true
        case ^RenderPass: return check_render_pass_gather(v, iteration_curr + 1, iteration_limit)
    }
    return // Impossible to reach but whatever
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

// Releases GPU memory
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

bind_framebuffer_gen :: proc(frame_buffer: ^FrameBuffer) {
    id, id_ok := frame_buffer.id.?
    if !id_ok do gen_framebuffer(&id)
    gl.BindFramebuffer(gl.FRAMEBUFFER, id)
}

bind_framebuffer :: proc(frame_buffer: FrameBuffer) {
    id, id_ok := frame_buffer.id.?
    if !id_ok {
        dbg.log(.ERROR, "Frame buffer could not be bound")
        return
    }

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

    bind_framebuffer_gen(frame_buffer)
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