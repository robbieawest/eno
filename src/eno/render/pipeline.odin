package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../resource"
import "../utils"

import "core:fmt"
import "core:slice"
import "base:intrinsics"
import "core:strings"


RenderPipeline :: struct {
    frame_buffers: [dynamic]^FrameBuffer,
    passes: [dynamic]^RenderPass,
    pre_passes: [dynamic]^PreRenderPass,
    shader_store: RenderShaderStore,
}

// Default render pipeline has no passes
init_render_pipeline :: proc(buffers: ..FrameBuffer, allocator := context.allocator) {
    Context.pipeline.frame_buffers = make([dynamic]^FrameBuffer, allocator=allocator)
    add_framebuffers(..buffers, allocator=allocator)

    Context.pipeline.passes = make([dynamic]^RenderPass, allocator=allocator)
    Context.pipeline.pre_passes = make([dynamic]^PreRenderPass, allocator=allocator)
    Context.pipeline.shader_store = init_shader_store(allocator)
    return
}

// Copies each framebuffer
add_framebuffers :: proc(buffers: ..FrameBuffer, allocator := context.allocator) {
    for buffer in buffers {
        new_buf := new(FrameBuffer, allocator=allocator)
        new_buf^ = buffer
        append_elems(&Context.pipeline.frame_buffers, new_buf)
    }
}

add_render_passes :: proc(passes: ..RenderPass) {
    for pass, i in passes {
        new_pass := new(RenderPass, allocator=Context.pipeline.passes.allocator)
        new_pass^ = pass
        append(&Context.pipeline.passes, new_pass)
    }
}

add_render_passes_ptr :: proc(passes: ..^RenderPass) {
    append_elems(&Context.pipeline.passes, ..passes)
}

add_pre_render_passes :: proc(passes: ..PreRenderPass, allocator := context.allocator) -> (ok: bool) {
    for pass, i in passes {
        new_pass := new(PreRenderPass, allocator=allocator)
        new_pass^ = pass
        append(&Context.pipeline.pre_passes, new_pass)
    }

    return true
}


// Releases GPU memory
destroy_pipeline :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) {
    pipeline := Context.pipeline
    for &fbo in pipeline.frame_buffers do destroy_framebuffer(fbo)
    delete(pipeline.frame_buffers)

    for pre_pass in pipeline.pre_passes do destroy_pre_render_pass(pre_pass^, allocator)
    delete(pipeline.pre_passes)

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

DepthFunc :: enum u8 {
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
    FRONT_AND_BACK
}

FaceCulling :: enum u8 {
    FRONT,
    BACK,
    FRONT_AND_BACK,
    ADAPTIVE  // Adaptive culls faces for the current draw based on if the material is double sided or not
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
    depth_func: Maybe(DepthFunc),
    polygon_mode: Maybe(PolygonMode),
    front_face: FrontFaceMode,
    face_culling: Maybe(FaceCulling),
    disable_depth_test: bool,
    stencil_test: bool,
    render_skybox: bool,
    viewport: Maybe([4]i32),
    clear: ClearMask,
    clear_colour: Maybe([4]f32),
    multisample: bool
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

RenderPassShaderGenerate :: union {
    LightingShaderGenerateConfig,
    GBufferShaderGenerateConfig
}

LightingShaderGenerateConfig :: struct {
    // Fill
}

GBufferShaderGenerateConfig :: struct {
    outputs: GBufferInfo
}

RenderPassShaderGather :: union #no_nil {
    RenderPassShaderGenerate,
    ^RenderPass
}

// It's called post process but it doesn't need to be "post"
// Just about taking texture(s) and returning another texture
PostProcessPass :: struct {
    render_targets: [dynamic]RenderTarget,
    render_inputs: [dynamic]^Attachment,
    shader: resource.ResourceIdent
}

make_post_process_pass :: proc(
    manager: ^resource.ResourceManager,
    shader: resource.ShaderProgram,
    allocator := context.allocator
) -> (pass: PostProcessPass, ok: bool) {
    pass.shader = resource.add_shader_pass(manager, shader) or_return

    pass.render_targets = make([dynamic]RenderTarget, allocator=allocator)
    pass.render_inputs = make([dynamic]^Attachment, allocator=allocator)

    ok = true
    return
}

add_render_targets :: proc(pass: ^PostProcessPass, targets: ..RenderTarget) {
    append_elems(&pass.render_targets, ..targets)
}

add_render_inputs :: proc(pass: ^PostProcessPass, inputs: ..^Attachment) {
    append_elems(&pass.render_inputs, ..inputs)
}

make_ssao_post_process_pass :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (pass: PostProcessPass, ok: bool) {

    

    ok = true
    return
}

GBufferComponent :: enum u32 {
    POSITION,
    NORMAL,
    DEPTH,  // Todo make sure depth is fully supported in gbuffer framebuffer
    // extend
}
GBufferInfo :: bit_set[GBufferComponent; u32]

TextureStorage :: struct{ internal_format: i32, format: u32, type: u32 }
GBufferComponentStorage := [GBufferComponent]TextureStorage {
    .POSITION = { gl.RGBA16F, gl.RGBA, gl.FLOAT },
    .NORMAL = { gl.RGBA16F, gl.RGBA, gl.FLOAT },
    .DEPTH = { gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT }
    // Colour = gl.RGBA, gl.RGBA, UNSIGNED BYTE
    // ...
}

// Create's new framebuffer to house gbuffer
// Defining a G-Buffer as a collection of one or more textures containing mesh data, not necessarily to be used for deferred rendering
make_gbuffer_passes :: proc(w, h: i32, info: GBufferInfo, allocator := context.allocator) -> (ok: bool) {

    if info == {} {
        dbg.log(.ERROR, "Attempting to create gbuffer with no components")
        return
    }

    framebuffer := make_framebuffer(w, h, allocator)
    bind_framebuffer(framebuffer) or_return

    tex_properties := make(resource.TextureProperties, allocator=allocator)
    defer delete(tex_properties)
    tex_properties[.MIN_FILTER] = .NEAREST
    tex_properties[.MAG_FILTER] = .NEAREST

    // Allocates textures in order of the GBufferComponent enum
    // Attachment order is the same, multiple render targets are the same
    // Not doing any funny packing

    // Stencil not supported yet
    last_colour_loc: u32 = 0; depth_used := false; stencil_used := false
    for component in GBufferComponent {
        if component in info {
            storage := GBufferComponentStorage[component]
            texture := resource.Texture{
                name = fmt.aprintf("GBuffer Texture Component %v", component),
                image = resource.Image{ w=w, h=h },
                type = .TWO_DIM,
                properties = utils.copy_map(tex_properties)
            }
            texture.gpu_texture = make_texture(texture, internal_format=storage.internal_format, format=storage.format, type=storage.type)

            attachment: Attachment
            attachment.data = texture
            switch component {
                case .NORMAL, .POSITION:
                    attachment.type = .COLOUR
                    if last_colour_loc == 31 {
                        dbg.log(.ERROR, "Max colour attachments reached")
                        return
                    }
                    last_colour_loc += 1
                    attachment.id = gl.COLOR_ATTACHMENT0 + last_colour_loc
                case .DEPTH:
                    if depth_used {  // Forward compat
                        dbg.log(.ERROR, "Depth attachment already used")
                        return
                    }

                    depth_used = true
                    attachment.type = .DEPTH
                    attachment.id = gl.DEPTH_ATTACHMENT
            }
            framebuffer_add_attachments(&framebuffer, attachment)
            check_framebuffer_status(framebuffer) or_return
        }
    }
    check_framebuffer_status(framebuffer) or_return

    attachments, _ := slice.map_keys(framebuffer.attachments, allocator=allocator); defer delete(attachments)
    framebuffer_draw_attachments(framebuffer, ..attachments, allocator=allocator) or_return
    check_framebuffer_status(framebuffer) or_return

    add_framebuffers(framebuffer, allocator=allocator)
    add_render_passes(
        make_render_pass(
            frame_buffer = Context.pipeline.frame_buffers[len(Context.pipeline.frame_buffers) - 1],
            shader_gather=RenderPassShaderGenerate(GBufferShaderGenerateConfig{ info }),
            mesh_gather=RenderPassQuery{ material_query =
                proc(material: resource.Material, type: resource.MaterialType) -> bool {
                    return type.alpha_mode != .BLEND && !type.double_sided
                }
            },
            properties=RenderPassProperties{
                geometry_z_sorting = .ASC,
                face_culling = FaceCulling.BACK,
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
            name  = "GBuffer Opaque Single Sided Pass",
            allocator=allocator
        ) or_return
    )
    add_render_passes(
        make_render_pass(
            frame_buffer = Context.pipeline.frame_buffers[len(Context.pipeline.frame_buffers) - 1],
            shader_gather=Context.pipeline.passes[len(Context.pipeline.passes) - 1],
            mesh_gather=RenderPassQuery{ material_query =
                proc(material: resource.Material, type: resource.MaterialType) -> bool {
                    return type.alpha_mode != .BLEND && type.double_sided
                }
            },
            properties=RenderPassProperties{
                geometry_z_sorting = .ASC,
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
            name="GBuffer Opaque Double Sided Pass",
            allocator=allocator
        ) or_return
    )

    ok = true
    return
}


// Don't think this is needed
AttachmentOutputChannel :: enum u32 {
    R,
    G,
    B,
    A,
    DEPTH,
    STENCIL
}

RenderTarget :: struct {
    framebuffer: ^FrameBuffer,
    attachment: ^Attachment,
    channels: bit_set[AttachmentOutputChannel; u32]
}


// Structure may be too simple
RenderPass :: struct {
    frame_buffer: ^FrameBuffer,
    // If ^RenderPass, use the mesh data queried in that render pass
    // When constructing a render pass, if mesh_gather : ^RenderPass then it will follow back through the references to find a RenderPassQuery
    mesh_gather: RenderPassMeshGather,
    shader_gather: RenderPassShaderGather,  // Used only to generate shader passes with
    properties: RenderPassProperties,
    name: string
}

// todo destroy_render_pass


// Populate this when needed
make_render_pass :: proc(
    shader_gather: RenderPassShaderGather,
    name: string,
    frame_buffer: ^FrameBuffer = nil,  // Nil corresponds to default sdl framebuffer
    mesh_gather: RenderPassMeshGather = nil,  // Nil corresponds to default return all mesh query
    properties: RenderPassProperties = {},
    allocator := context.allocator
) -> (pass: RenderPass, ok: bool) {
    dbg.log(.INFO, "Creating render pass")
    pass.frame_buffer = frame_buffer
    pass.mesh_gather = mesh_gather
    pass.shader_gather = shader_gather
    pass.properties = properties
    pass.name = strings.clone(name, allocator)

    if pass.mesh_gather != nil && !check_render_pass_mesh_gather(&pass, 0, len(Context.pipeline.passes)) {
        dbg.log(.ERROR, "Render pass mesh gather must end in a RenderPassQuery")
        return
    }

    if !check_render_pass_shader_gather(&pass, 0, len(Context.pipeline.passes)) {
        dbg.log(.ERROR, "Render pass shader gather must end in a RenderPassShaderGenerate enum")
        return
    }


    ok = true
    return
}

@(private)
check_render_pass_mesh_gather :: proc(pass: ^RenderPass, iteration_curr: int, iteration_limit: int) -> (ok: bool) {
    switch v in pass.mesh_gather {
        case RenderPassQuery: return true
        case ^RenderPass:
            if iteration_curr == iteration_limit do return false
            return check_render_pass_mesh_gather(v, iteration_curr + 1, iteration_limit)
        case nil: dbg.log(.ERROR, "Render pass mesh gather is nil")
    }
    return
}

@(private)
check_render_pass_shader_gather :: proc(pass: ^RenderPass, iteration_curr: int, iteration_limit: int) -> (ok: bool) {
    switch v in pass.shader_gather {
        case ^RenderPass:
            if iteration_curr == iteration_limit do return false
            return check_render_pass_shader_gather(v, iteration_curr + 1, iteration_limit)
        case RenderPassShaderGenerate: return true
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
        case resource.Texture:
            release_texture(data.gpu_texture)
            resource.destroy_texture(&data)
        case RenderBuffer: release_render_buffer(&data)
    }
}


AttachmentData :: union {
    resource.Texture,
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

// Note sure why this takes a ptr
destroy_framebuffer :: proc(frame_buffer: ^FrameBuffer, release_attachments := true) {
    if release_attachments do for _, &attachment in frame_buffer.attachments do destroy_attachment(&attachment)
    delete(frame_buffer.attachments)
    if id, id_ok := frame_buffer.id.?; id_ok do release_framebuffer(frame_buffer^)
}

framebuffer_add_attachments :: proc(framebuffer: ^FrameBuffer, attachments: ..Attachment) -> (ok: bool) {
    if framebuffer == nil {
        dbg.log(.ERROR, "Framebuffer is nil")
        return
    }

    dbg.log(.INFO, "Adding attachments to framebuffer: %#v", framebuffer)

    bind_framebuffer(framebuffer^) or_return
    for attachment in attachments {
        dbg.log(.INFO, "Adding attachment %#v", attachment)
        bind_attachment_to_framebuffer(framebuffer^, attachment)
        framebuffer.attachments[attachment.id] = attachment
    }
    return true
}

bind_attachment_to_framebuffer :: proc(framebuffer: FrameBuffer, attachment: Attachment) -> (ok: bool) {
    switch attachment_data in attachment.data {
        case RenderBuffer:
            dbg.log(.ERROR, "Unimplemented")
            return
        case resource.Texture:
            fbo, fbo_ok := framebuffer.id.?
            if !fbo_ok {
                dbg.log(.ERROR, "Framebuffer is not yet transferred")
                return
            }
            bind_texture_to_frame_buffer(fbo, attachment_data, attachment.type, attachment_id=attachment.id)
    }

    return true
}

// Attachments are gl.COLOR_ATTACHMENT0 etc.
framebuffer_draw_attachments :: proc(framebuffer: FrameBuffer, attachments: ..u32, allocator := context.allocator) -> (ok: bool) {
    bind_framebuffer(framebuffer) or_return
    if len(attachments) != 0 {
        for attachment, i in attachments {
            if attachment not_in framebuffer.attachments {
                dbg.log(.ERROR, "Attachment index is not valid: '%d'", attachment)
                return
            }
        }
        draw_buffers(..attachments, allocator=allocator)
    }
    else {
        attachments, _ := slice.map_keys(framebuffer.attachments, allocator=allocator)
        defer delete(attachments, allocator=allocator)
        draw_buffers(..attachments, allocator=allocator)
    }

    bind_default_framebuffer()
    return true
}

PreRenderPassInput :: union {
    IBLInput
}

IBLInput :: struct {
    // ... add later?
}

PreRenderPass :: struct {
    input: PreRenderPassInput,
    frame_buffers: []^FrameBuffer
}

destroy_pre_render_pass :: proc(pre_pass: PreRenderPass, allocator := context.allocator) {
    delete(pre_pass.frame_buffers, allocator=allocator)
}

make_pre_render_pass :: proc(
    pipeline: RenderPipeline,
    input: PreRenderPassInput,
    frame_buffers: ..^FrameBuffer,
    allocator := context.allocator
) -> (pass: PreRenderPass, ok: bool) {
    buffers := make([dynamic]^FrameBuffer, allocator=allocator)

    pass.frame_buffers = slice.clone(frame_buffers)
    pass.input = input

    ok = true
    return
}