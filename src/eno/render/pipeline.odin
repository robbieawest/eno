package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../resource"
import "../utils"
import "../standards"

import "core:fmt"
import "core:slice"
import "base:intrinsics"
import "core:strings"
import "core:mem"


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

get_render_pass :: proc(name: string) -> (pass: ^RenderPass, ok: bool) {
    for render_pass in Context.pipeline.passes {
        if strings.compare(render_pass.name, name) == 0 do return render_pass, true
    }
    dbg.log(.ERROR, "Could not find render pass of name '%s'", name)
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

RenderPassMeshGather :: union {
    RenderPassQuery,
    ^RenderPass,
    SinglePrimitiveMesh
 }

SinglePrimitiveMeshType :: enum {
    CUBE,
    QUAD,
    TRIANGLE
}

// These point to render context global meshes, the materials are completely blank.
SinglePrimitiveMesh :: struct {
    type: SinglePrimitiveMeshType,
    world: standards.WorldComponent
}

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
    RenderPassShaderGenerate,  // Shader pass generator will be pre-defined
    ^RenderPass,
    GenericShaderPassGenerator
}

GenericShaderPassGenerator :: #type proc(
    manager: ^resource.ResourceManager,
    vertex_layout: ^resource.VertexLayout,
    material_type: ^resource.MaterialType,
    options: rawptr,
    allocator: mem.Allocator,
) -> (resource.ShaderProgram, bool)

/*
// todo delete mentions of post process pass
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
*/


// Structure may be too simple
RenderPass :: struct {
    frame_buffer: ^FrameBuffer,
    // If ^RenderPass, use the mesh data queried in that render pass
    // When constructing a render pass, if mesh_gather : ^RenderPass then it will follow back through the references to find a RenderPassQuery
    mesh_gather: RenderPassMeshGather,
    shader_gather: RenderPassShaderGather,  // Used only to generate shader passes with
    properties: RenderPassProperties,
    inputs: []RenderPassIO,
    outputs: []RenderPassIO,
    executions: []RenderPassExecution,  // Not necessary for a pass, only used if there are multiple executions of a pass needed, with different uniforms set on each execution
    // todo bindables definitions, e.g. uniform (use camera data, light data) or what and specify binding location.
    // todo ^ custom specification for gather of uniform data. e.g. from render pass output (a texture) or a generic function you can tune
    name: string
}

AttachmentID :: struct {
    type: AttachmentType,
    offset: u32,
}

gl_conv_attachment_id :: proc(id: AttachmentID) -> (gl_id: u32, ok: bool) {
    switch id.type {
        case .COLOUR:
            if id.offset >= 32 {
                dbg.log(.ERROR, "Attachment colour offset cannot be >= 32")
                return
            }
            gl_id = gl.COLOR_ATTACHMENT0 + id.offset
        case .DEPTH: gl_id = gl.DEPTH_ATTACHMENT
        case .STENCIL: gl_id = gl.STENCIL_ATTACHMENT
        case .DEPTH_STENCIL: gl_id = gl.DEPTH_STENCIL_ATTACHMENT
    }

    ok = true
    return
}

// Really just defines a sampler uniform that will always be attempted to be bound to the identifier
RenderPassIO :: struct {
    framebuffer: ^FrameBuffer,
    attachment: AttachmentID,
    identifier: string
}

RenderPassExecution :: struct {
    uniforms: []UniformData
}

// todo destroy_render_pass


// Populate this when needed
make_render_pass :: proc(
    shader_gather: RenderPassShaderGather,
    name: string,
    frame_buffer: ^FrameBuffer = nil,  // Nil corresponds to default sdl framebuffer
    mesh_gather: RenderPassMeshGather = nil,  // Nil corresponds to default return all mesh query
    properties: RenderPassProperties = {},
    inputs: []RenderPassIO = {},
    outputs: []RenderPassIO = {},
    executions: []RenderPassExecution = {},
    allocator := context.allocator
) -> (pass: RenderPass, ok: bool) {
    dbg.log(.INFO, "Creating render pass")
    pass.frame_buffer = frame_buffer
    pass.mesh_gather = mesh_gather
    pass.shader_gather = shader_gather
    pass.properties = properties
    pass.name = strings.clone(name, allocator)
    pass.inputs = slice.clone(inputs, allocator)
    pass.outputs = slice.clone(outputs, allocator)

    if len(executions) == 0 do pass.executions = make([]RenderPassExecution, 1, allocator)
    else do pass.executions = slice.clone(executions, allocator)

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
        case RenderPassQuery, SinglePrimitiveMesh: return true
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
        case RenderPassShaderGenerate, GenericShaderPassGenerator: return true
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