package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../ecs"
import "../resource"

import "core:slice"
import "core:reflect"
import "core:strings"
import "base:intrinsics"
import utils "../utils"

FrameBufferID :: u32  // Index into RenderPipeline.frame_buffers - checked
RenderPipeline :: struct {
    frame_buffers: []FrameBuffer,
    passes: []RenderPass,
    shader_store: RenderShaderStore,
    pre_passes: []PreRenderPass
}

// Default render pipeline has no passes
init_render_pipeline :: proc{ init_render_pipeline_no_bufs, init_render_pipeline_bufs }

// Default render pipeline has no passes
init_render_pipeline_no_bufs :: proc(#any_int n_render_passes: int, allocator := context.allocator) -> (ret: RenderPipeline) {
    ret.passes = make([]RenderPass, n_render_passes, allocator=allocator)
    ret.shader_store = init_shader_store(allocator)
    return
}

// Default render pipeline has no passes
init_render_pipeline_bufs :: proc(#any_int n_render_passes: int, buffers: []FrameBuffer, allocator := context.allocator) -> (ret: RenderPipeline) {
    ret.frame_buffers = slice.clone(buffers, allocator=allocator)
    ret.passes = make([]RenderPass, n_render_passes, allocator=allocator)
    ret.shader_store = init_shader_store(allocator)
    return
}

add_render_passes :: proc(pipeline: ^RenderPipeline, passes: ..RenderPass, allocator := context.allocator) -> (ok: bool) {
    if len(passes) != len(pipeline.passes) {
        dbg.log(.ERROR, "Did not give enough render passes")
        return
    }

    for pass, i in passes {
        if pass.frame_buffer != nil && int(pass.frame_buffer.?) >= len(pipeline.frame_buffers) {
            dbg.log(.ERROR, "Render pass framebuffer id '%d' does not correspond to a framebuffer in the pipeline", pass.frame_buffer)
            return
        }
        pipeline.passes[i] = pass
    }

    return true
}


// Releases GPU memory
destroy_pipeline :: proc(pipeline: ^RenderPipeline, manager: ^resource.ResourceManager) {
    for &fbo in pipeline.frame_buffers do destroy_framebuffer(&fbo)
    delete(pipeline.frame_buffers)
    delete(pipeline.passes)
    destroy_shader_store(manager, pipeline.shader_store)
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
MaterialQuery :: #type proc(resource.Material, resource.MaterialType) -> bool
RenderPassQuery :: struct {
    component_queries: []struct{ label: string, data: rawptr },
    material_query: Maybe(MaterialQuery)
}

// Maybe remove? Not sure it is needed
apply_material_query :: proc(
    manager: ^resource.ResourceManager,
    mat_query: Maybe(MaterialQuery),
    meshes: []^resource.Mesh,
    allocator := context.allocator
) -> (new_meshes: []^resource.Mesh, ok: bool) {
    query, query_ok := mat_query.?
    if !query_ok do return new_meshes, true

    new_meshes_dyn := make([dynamic]^resource.Mesh, allocator=allocator)

    for mesh in meshes {
        mat_type := resource.get_material(manager, mesh.material.type) or_return
        if query(mesh.material, mat_type^) do append(&new_meshes_dyn, mesh)
    }
    return new_meshes_dyn[:], true
}

RenderPassMeshGather :: union { RenderPassQuery, ^RenderPass }

// Extend
RenderPassShaderGenerate :: enum {
    NO_GENERATE,
    DEPTH_ONLY,
    LIGHTING
}

RenderPassShaderGather :: union #no_nil {
    RenderPassShaderGenerate,
    ^RenderPass
}

// Structure may be too simple
RenderPass :: struct {
    frame_buffer: Maybe(FrameBufferID),
    // If ^RenderPass, use the mesh data queried in that render pass
    // When constructing a render pass, if mesh_gather : ^RenderPass then it will follow back through the references to find a RenderPassQuery
    mesh_gather: RenderPassMeshGather,
    shader_gather: RenderPassShaderGather,  // Used only to generate shader passes with
    properties: RenderPassProperties,
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


make_framebuffer :: proc(w, h: i32, allocator := context.allocator) -> (frame_buffer: FrameBuffer) {
    frame_buffer.w = w
    frame_buffer.h = h
    frame_buffer.id = gen_framebuffer()
    frame_buffer.attachments = make(map[u32]Attachment, allocator=allocator) // todo check needed
    return
}

destroy_framebuffer :: proc(frame_buffer: ^FrameBuffer) {
    for _, &attachment in frame_buffer.attachments do destroy_attachment(&attachment)
    delete(frame_buffer.attachments)
    if id, id_ok := frame_buffer.id.?; id_ok do release_framebuffer(frame_buffer^)
}




RenderType :: enum {
    COLOUR = intrinsics.constant_log2(gl.COLOR_BUFFER_BIT),
    DEPTH = intrinsics.constant_log2(gl.DEPTH_BUFFER_BIT),
    STENCIL = intrinsics.constant_log2(gl.STENCIL_BUFFER_BIT)
}


PreRenderPassInput :: union {
    IBLInput
}

IBLInput :: struct {
    // ... add later?
}

PreRenderPass :: struct {
    input: PreRenderPassInput,
    frame_buffers: []FrameBufferID
}

make_pre_render_pass :: proc(
    pipeline: RenderPipeline,
    input: PreRenderPassInput,
    frame_buffers: ..FrameBufferID,
    allocator := context.allocator
) -> (pass: PreRenderPass, ok: bool) {
    buffers := make([dynamic]FrameBufferID, allocator=allocator)
    for frame_buffer in frame_buffers {
        if int(frame_buffer) >= len(pipeline.frame_buffers) {
            dbg.log(.ERROR, "Frame buffer points outside of the pipeline framebuffers")
            return
        }
        append(&buffers, frame_buffer)
    }

    pass.frame_buffers = buffers[:]
    pass.input = input

    ok = true
    return
}