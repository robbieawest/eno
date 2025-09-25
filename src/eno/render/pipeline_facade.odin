package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../resource"
import "../utils"
import "../standards"

import "core:mem"
import "core:fmt"
import "core:slice"


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
make_gbuffer_passes :: proc(w, h: i32, info: GBufferInfo, allocator := context.allocator) -> (normal_output: RenderPassIO, ok: bool) {

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
                name = fmt.aprintf("GBuffer Texture Component %v", component, allocator=allocator),
                image = resource.Image{ w=w, h=h },
                type = .TWO_DIM,
                properties = utils.copy_map(tex_properties, allocator=allocator)
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
    gbuf_fbo := Context.pipeline.frame_buffers[len(Context.pipeline.frame_buffers) - 1]
    add_render_passes(
        make_render_pass(
            frame_buffer = gbuf_fbo,
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

    normal_output = RenderPassIO{ framebuffer=gbuf_fbo, attachment=AttachmentID{ .COLOUR, 0 }, identifier="GBuffer Opaque Double Sided Pass" }
    add_render_passes(
        make_render_pass(
            frame_buffer = gbuf_fbo,
            shader_gather=Context.pipeline.passes[len(Context.pipeline.passes) - 1],
            mesh_gather=RenderPassQuery{ material_query =
            proc(material: resource.Material, type: resource.MaterialType) -> bool {
                return type.alpha_mode != .BLEND && type.double_sided
            }
            },
            properties=RenderPassProperties{
                geometry_z_sorting = .ASC,
            },
            name=normal_output.identifier,
            allocator=allocator
        ) or_return
    )

    ok = true
    return
}


make_ssao_passes :: proc(w, h: i32, gbuf_output: RenderPassIO, allocator := context.allocator) -> (ok: bool) {

    framebuffer := make_framebuffer(w, h, allocator)
    bind_framebuffer(framebuffer) or_return

    /* todo add to render
    normals_attachment_id := gl.COLOR_ATTACHMENT0 + normals_attachment_offset
    normals_attachment, normals_ok := gbuffer_framebuffer.attachments[normals_attachment_id]
    if !normals_ok {
        dbg.log(.ERROR, "Normals attachment not found")
        return
    }
    normals_texture, normals_is_tex := normals_attachment.data.(resource.Texture)
    if !normals_is_tex {
        dbg.log(.ERROR, "Normals attachment needs to be texture for SSAO")
        return
    }

    depth_attachment, depth_ok := gbuffer_framebuffer.attachments[gl.DEPTH_ATTACHMENT]
    if !depth_ok {
        dbg.log(.ERROR, "Depth attachment not available in gbuffer framebuffer")
        return
    }
    depth_texture, depth_is_tex := depth_attachment.data.(resource.Texture)
    if !depth_is_tex {
        dbg.log(.ERROR, "Depth attachment needs to be texture for SSAO")
        return
    }

    */

    tex_properties := make(resource.TextureProperties, allocator=allocator)
    defer delete(tex_properties)
    tex_properties[.MIN_FILTER] = .NEAREST
    tex_properties[.MAG_FILTER] = .NEAREST


    ssao_texture := resource.Texture{
        name = fmt.aprintf("SSAO first pass texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_texture.gpu_texture = make_texture(ssao_texture, internal_format=gl.R32F, format=gl.RED, type=gl.FLOAT)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_texture, id = gl.COLOR_ATTACHMENT0, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return

    ssao_blurred_texture := resource.Texture{
        name = fmt.aprintf("SSAO second pass texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_blurred_texture.gpu_texture = make_texture(ssao_blurred_texture, internal_format=gl.R32F, format=gl.RED, type=gl.FLOAT)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_blurred_texture, id = gl.COLOR_ATTACHMENT1, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return

    attachments, _ := slice.map_keys(framebuffer.attachments, allocator=allocator); defer delete(attachments)
    framebuffer_draw_attachments(framebuffer, ..attachments, allocator=allocator) or_return
    check_framebuffer_status(framebuffer) or_return

    add_framebuffers(framebuffer, allocator=allocator)

    ssao_fbo := Context.pipeline.frame_buffers[len(Context.pipeline.frame_buffers) - 1]
    add_render_passes(
        make_render_pass(
            shader_gather = generate_ssao_first_shader_pass,
            name = "SSAO first pass",
            frame_buffer = ssao_fbo,
            mesh_gather = SinglePrimitiveMesh{ type=.QUAD },  // doesn't need to care about transforms, since the SSAO shader does not care
            properties=RenderPassProperties{
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
                disable_depth_test=true,
            },
            inputs = []RenderPassIO {
                gbuf_output,
                { gbuf_output.framebuffer, AttachmentID{ type=.DEPTH }, "gbDepth" },
            },
            outputs = []RenderPassIO {
                {
                    ssao_fbo,
                    AttachmentID{ .COLOUR, 0 },
                    "SSAOColour"
                }
            }
        ) or_return,
        make_render_pass(
            shader_gather = generate_ssao_second_shader_pass,
            name = "SSAO second pass",
            frame_buffer = ssao_fbo,
            mesh_gather = SinglePrimitiveMesh{ type=.QUAD },  // doesn't need to care about transforms, since the SSAO shader does not care
            properties=RenderPassProperties{
                face_culling = FaceCulling.BACK,
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
                disable_depth_test=true
            },
            inputs = []RenderPassIO{
                { ssao_fbo, AttachmentID{ type=.COLOUR }, "SSAOColour" },
            },
            outputs = []RenderPassIO {
                {
                    ssao_fbo,
                    AttachmentID{ .COLOUR, 1 },
                    "SSAOBlur"
                }

            }
        ) or_return
    )

    ok = true
    return
}

generate_ssao_first_shader_pass : GenericShaderPassGenerator : proc(
    manager: ^resource.ResourceManager,
    vertex_layout: ^resource.VertexLayout,
    material_type: ^resource.MaterialType,
    options: rawptr,
    allocator: mem.Allocator,
) -> (shader_pass: resource.ShaderProgram, ok: bool) {

    dbg.log(dbg.LogLevel.INFO, "Creating ssao first pass vertex shader")
    vert_id := generate_ssao_vert_shader(manager, vertex_layout, allocator) or_return

    dbg.log(dbg.LogLevel.INFO, "Creating ssao first pass fragment shader")
    frag_id := generate_ssao_first_pass_frag_shader(manager, allocator) or_return

    // Grabbing shaders here makes it impossible to compile a shader twice
    vert := resource.get_shader(manager, vert_id) or_return
    frag := resource.get_shader(manager, frag_id) or_return

    if vert.id == nil do compile_shader(vert) or_return
    else do dbg.log(.INFO, "Vertex shader already compiled")
    if frag.id == nil do compile_shader(frag) or_return
    else do dbg.log(.INFO, "Fragment shader already compiled")

    shader_pass = resource.init_shader_program()
    shader_pass.shaders[.VERTEX] = vert_id
    shader_pass.shaders[.FRAGMENT] = frag_id

    ok = true
    return
}

generate_ssao_vert_shader :: proc(manager: ^resource.ResourceManager, layout: ^resource.VertexLayout, allocator := context.allocator) -> (vert_id: resource.ResourceIdent, ok: bool) {
    // todo some layout checks/defines
    // this is temp test code
    shader := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "ssao/ssao.vert", .VERTEX, allocator) or_return
    return resource.add_shader(manager, shader)
}

generate_ssao_first_pass_frag_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (frag_id: resource.ResourceIdent, ok: bool) {
    shader := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "ssao/ssao_first_pass.frag", .FRAGMENT, allocator) or_return
    return resource.add_shader(manager, shader)
}

generate_ssao_second_shader_pass : GenericShaderPassGenerator : proc(
    manager: ^resource.ResourceManager,
    vertex_layout: ^resource.VertexLayout,
    material_type: ^resource.MaterialType,
    options: rawptr,
    allocator: mem.Allocator,
) -> (shader_pass: resource.ShaderProgram, ok: bool) {

    dbg.log(dbg.LogLevel.INFO, "Creating ssao second pass vertex shader")
    vert_id := generate_ssao_vert_shader(manager, vertex_layout, allocator) or_return

    dbg.log(dbg.LogLevel.INFO, "Creating ssao second pass fragment shader")
    frag_id := generate_ssao_second_pass_frag_shader(manager, allocator) or_return

    // Grabbing shaders here makes it impossible to compile a shader twice
    vert := resource.get_shader(manager, vert_id) or_return
    frag := resource.get_shader(manager, frag_id) or_return

    if vert.id == nil do compile_shader(vert) or_return
    else do dbg.log(.INFO, "Vertex shader already compiled")
    if frag.id == nil do compile_shader(frag) or_return
    else do dbg.log(.INFO, "Fragment shader already compiled")

    shader_pass = resource.init_shader_program()
    shader_pass.shaders[.VERTEX] = vert_id
    shader_pass.shaders[.FRAGMENT] = frag_id

    ok = true
    return
}

generate_ssao_second_pass_frag_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (frag_id: resource.ResourceIdent, ok: bool) {
    shader := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "ssao/ssao_second_pass.frag", .FRAGMENT, allocator) or_return
    return resource.add_shader(manager, shader)
}



