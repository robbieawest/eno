package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../resource"
import "../utils"
import "../standards"
import win "../window"

import "core:mem"
import "core:fmt"
import "core:slice"

import "core:math/rand"
import "core:math/linalg"


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
    .NORMAL = { gl.RGBA8, gl.RGBA, gl.UNSIGNED_INT },
    .DEPTH = { gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT }
// Colour = gl.RGBA, gl.RGBA, UNSIGNED BYTE
// ...
}

// Create's new framebuffer to house gbuffer
// Defining a G-Buffer as a collection of one or more textures containing mesh data, not necessarily to be used for deferred rendering
make_gbuffer_passes :: proc(w, h: i32, info: GBufferInfo, allocator := context.allocator) -> (normal_output: Maybe(RenderPassIO), ok: bool) {

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
    tex_properties[.WRAP_S] = .CLAMP_EDGE
    tex_properties[.WRAP_T] = .CLAMP_EDGE

    // Allocates textures in order of the GBufferComponent enum
    // Attachment order is the same, multiple render targets are the same
    // Not doing any funny packing

    outputs := make([dynamic]RenderPassIO, allocator=allocator)

    add_framebuffers(framebuffer, allocator=allocator)
    gbuf_fbo := Context.pipeline.frame_buffers[len(Context.pipeline.frame_buffers) - 1]

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

            io: RenderPassIO
            io.framebuffer = gbuf_fbo

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
                io.attachment = AttachmentID{ .COLOUR, last_colour_loc }
                if component == .NORMAL {
                    io.identifier = "gbNormal"
                    normal_output = io
                }
                else do io.identifier = "gbPosition"
            case .DEPTH:
                if depth_used {  // Forward compat
                    dbg.log(.ERROR, "Depth attachment already used")
                    return
                }

                depth_used = true
                attachment.type = .DEPTH
                attachment.id = gl.DEPTH_ATTACHMENT
                io.attachment = AttachmentID{ type=.DEPTH }
                io.identifier = "gbDepth"
            }
            framebuffer_add_attachments(gbuf_fbo, attachment)
            check_framebuffer_status(gbuf_fbo^) or_return

            append(&outputs, io)
        }
    }
    check_framebuffer_status(gbuf_fbo^) or_return

    attachments, _ := slice.map_keys(gbuf_fbo.attachments, allocator=allocator); defer delete(attachments)
    framebuffer_draw_attachments(gbuf_fbo^, ..attachments, allocator=allocator) or_return
    check_framebuffer_status(gbuf_fbo^) or_return

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
        outputs = outputs[:],
        allocator=allocator
        ) or_return
    )

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
            outputs = outputs[:],
            name="GBuffer Opaque Double Sided Pass",
            allocator=allocator
        ) or_return
    )

    ok = true
    return
}


make_ssao_passes :: proc(w, h: i32, gbuf_output: RenderPassIO, allocator := context.allocator) -> (ssao_output: RenderPassIO, ok: bool) {

    // This always stores a packed RGBA8 where RGB = bent normal and A = ambient occlusion
    // The first pass computes the unfiltered, noisy AO and BNs
    // The second performs a joint bilateral filter, depth + spatial for AO, depth + spatial + normal for BNs
    // All at full resolution, an extension could be to compute at half res, filter, then upscale - this is production ready
    // The joint bilateral filter is a seperable approximation (slight artifacts sometimes), to reduce O(N^2) to O(N)
    // ^this makes it technically a two-pass filter, but the "render pass" repeats the same draw but with a filter direction uniform set to true/false depending

    framebuffer := make_framebuffer(w, h, allocator)
    bind_framebuffer(framebuffer) or_return

    tex_properties := make(resource.TextureProperties, allocator=allocator)
    defer delete(tex_properties)
    tex_properties[.MIN_FILTER] = .LINEAR
    tex_properties[.MAG_FILTER] = .LINEAR
    tex_properties[.WRAP_S] = .CLAMP_EDGE
    tex_properties[.WRAP_T] = .CLAMP_EDGE

    ssao_unfiltered_texture := resource.Texture{
        name = fmt.aprintf("SSAO unfilted texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_unfiltered_texture.gpu_texture = make_texture(ssao_unfiltered_texture, internal_format=gl.RGBA8, format=gl.RGBA, type=gl.UNSIGNED_BYTE)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_unfiltered_texture, id = gl.COLOR_ATTACHMENT0, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return


    ssao_filtered_texture := resource.Texture{
        name = fmt.aprintf(" SSAO filtered texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_filtered_texture.gpu_texture = make_texture(ssao_filtered_texture, internal_format=gl.RGBA8, format=gl.RGBA, type=gl.UNSIGNED_BYTE)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_filtered_texture, id = gl.COLOR_ATTACHMENT1, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return


    attachments, _ := slice.map_keys(framebuffer.attachments, allocator=allocator); defer delete(attachments)
    framebuffer_draw_attachments(framebuffer, ..attachments, allocator=allocator) or_return
    check_framebuffer_status(framebuffer) or_return

    add_framebuffers(framebuffer, allocator=allocator)

    ssao_fbo := Context.pipeline.frame_buffers[len(Context.pipeline.frame_buffers) - 1]
    ssao_output = RenderPassIO {
        ssao_fbo,
        AttachmentID{ .COLOUR, 0 },
        "SSAOFilteredOut"
    }

    //@(static) filter_directions := [?]bool{false, true}
    filter_directions := make([]bool, 2, allocator)
    filter_directions[0] = false
    filter_directions[1] = true

     filter_direction_uniforms := slice.clone([]UniformData {
        {
            "filterDirection",
            resource.GLSLDataType.bool,
            bool,
            slice.clone(slice.reinterpret([]u8, filter_directions[:1]))
        //utils.to_bytes_comp(&f)
        },
        {
            "filterDirection",
            resource.GLSLDataType.bool,
            bool,
            slice.clone(slice.reinterpret([]u8, filter_directions[1:]))
        //utils.to_bytes_comp(&f)
        }
    })

    add_render_passes(
        make_render_pass(
            shader_gather = generate_ssao_first_shader_pass,
            name = "SSAO first pass",
            frame_buffer = ssao_fbo,
            mesh_gather = SinglePrimitiveMesh{ type=.QUAD },
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
                    "SSAOOut"
                }
            }
        ) or_return,
        make_render_pass(
            shader_gather = generate_ssao_second_shader_pass,
            name = "SSAO filter pass horizontal",
            frame_buffer = ssao_fbo,
            mesh_gather = SinglePrimitiveMesh{ type=.QUAD },
            properties=RenderPassProperties{
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
                disable_depth_test=true
            },
            inputs = []RenderPassIO{
                  { ssao_fbo, AttachmentID{ type=.COLOUR }, "SSAOOut" },
                  gbuf_output,
                  { gbuf_output.framebuffer, AttachmentID{ type=.DEPTH }, "gbDepth" },
            },
            outputs = []RenderPassIO {
                {
                    ssao_fbo,
                    AttachmentID{ .COLOUR, 1 },
                    "SSAOOut"
                }
            },
            executions = []RenderPassExecution{
                { filter_direction_uniforms[0:] },
            }
        ) or_return
    )
    horizontal_pass := Context.pipeline.passes[len(Context.pipeline.passes) - 1]

    add_render_passes(
        make_render_pass(
            shader_gather = horizontal_pass,
            name = "SSAO filter pass vertical",
            frame_buffer = ssao_fbo,
            mesh_gather = horizontal_pass,
            properties=RenderPassProperties{
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
                disable_depth_test=true
            },
            inputs = []RenderPassIO{
                { ssao_fbo, AttachmentID{ type = .COLOUR, offset = 1 }, "SSAOOut" },
                gbuf_output,
                { gbuf_output.framebuffer, AttachmentID{ type=.DEPTH }, "gbDepth" },
            },
            outputs = []RenderPassIO { ssao_output },
            executions = []RenderPassExecution{ { filter_direction_uniforms[:1] } }
        ) or_return

    )

    // Setup sampler uniform
    setup_ssao_uniforms(w, h, allocator=allocator) or_return

    ok = true
    return
}


SSAO_NUM_SAMPLES : u32 : 64
MAX_SSAO_SAMPLES: u32 : 128
SSAO_NOISE_W : u32 : 4
SSAO_SAMPLE_RADIUS : f32 : 0.5
SSAO_BIAS : f32 : 0.025
SSAO_KERNEL_UNIFORM :: "SSAOKernelSamples"
SSAO_NUM_SAMPLES_UNIFORM :: "SSAONumSamplesInKernel"
SSAO_NOISE_TEX_UNIFORM :: "SSAONoiseTex"
SSAO_W_UNIFORM :: "SSAOW"
SSAO_H_UNIFORM :: "SSAOH"
SSAO_NOISE_W_UNIFORM :: "SSAONoiseW"
SSAO_SAMPLE_RADIUS_UNIFORM :: "SSAOSampleRadius"
SSAO_BIAS_UNIFORM :: "SSAOBias"
SSAO_EVALUATE_BENT_NORM_UNIFORM :: "SSAOEvaluateBentNormal"
setup_ssao_uniforms :: proc(#any_int w, h: u32, num_kernel_samples := SSAO_NUM_SAMPLES, allocator := context.allocator) -> (ok: bool) {
    if num_kernel_samples > MAX_SSAO_SAMPLES {
        dbg.log(.ERROR, "Number of SSAO samples must not be greater than %d", MAX_SSAO_SAMPLES)
        return
    }

    kernel := make([][3]f32, num_kernel_samples, allocator=allocator)
    defer delete(kernel)
    for i in 0..<num_kernel_samples {
        sample: [3]f32 = { rand.float32() * 2 - 1, rand.float32() * 2 - 1, rand.float32() }
        sample = linalg.normalize(sample)
        sample *= rand.float32()
        kernel[i] = sample;
        /*
        scale := f32(i) / 64
        kernel[i] = sample * linalg.lerp(f32(0.1), 1.0, scale*scale)
        */
    }

    store_uniform(SSAO_NUM_SAMPLES_UNIFORM, resource.GLSLDataType.uint, SSAO_NUM_SAMPLES)
    store_uniform(SSAO_W_UNIFORM, resource.GLSLDataType.uint, w)
    store_uniform(SSAO_H_UNIFORM, resource.GLSLDataType.uint, h)
    store_uniform(SSAO_NOISE_W_UNIFORM, resource.GLSLDataType.uint, SSAO_NOISE_W)
    store_uniform(SSAO_KERNEL_UNIFORM, resource.GLSLFixedArray{ uint(MAX_SSAO_SAMPLES),  .vec3 }, kernel)
    store_uniform(SSAO_SAMPLE_RADIUS_UNIFORM, resource.GLSLDataType.float, SSAO_SAMPLE_RADIUS)
    store_uniform(SSAO_BIAS_UNIFORM, resource.GLSLDataType.float, SSAO_BIAS)

    noise_tex := make_ssao_noise_texture(allocator=allocator) or_return
    store_uniform(SSAO_NOISE_TEX_UNIFORM, resource.GLSLDataType.sampler2D, noise_tex)

    return true
}

make_ssao_noise_texture :: proc(#any_int noise_w : u32 = SSAO_NOISE_W, allocator := context.allocator) -> (tex: resource.Texture, ok: bool) {
    noise_size := noise_w * noise_w
    ssao_noise := make([][3]f32, noise_size, allocator=allocator)
    for i in 0..<noise_size do ssao_noise[i] = [3]f32{ rand.float32() * 2 - 1, rand.float32() * 2 - 1, 0.0 }

    tex_properties := make(map[resource.TextureProperty]resource.TexturePropertyValue, allocator=allocator)
    tex_properties[.WRAP_S] = .REPEAT
    tex_properties[.WRAP_T] = .REPEAT
    tex_properties[.MIN_FILTER] = .NEAREST
    tex_properties[.MAG_FILTER] = .NEAREST
    tex.properties = tex_properties
    tex.image = resource.Image{ w=i32(noise_w), h=i32(noise_w), pixel_data=raw_data(ssao_noise) }
    tex.gpu_texture = make_texture(tex, internal_format=gl.RGBA32F, format=gl.RGB, type=gl.FLOAT)

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

    shader_pass = resource.init_shader_program("SSAO first pass")
    shader_pass.shaders[.VERTEX] = vert_id
    shader_pass.shaders[.FRAGMENT] = frag_id

    ok = true
    return
}

generate_ssao_vert_shader :: proc(manager: ^resource.ResourceManager, layout: ^resource.VertexLayout, allocator := context.allocator) -> (vert_id: resource.ResourceIdent, ok: bool) {
    return resource.generate_shader(manager, .VERTEX, standards.SHADER_RESOURCE_PATH + "ssao/ssao.vert", allocator=allocator)
}

generate_ssao_first_pass_frag_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (frag_id: resource.ResourceIdent, ok: bool) {
    return resource.generate_shader(manager, .FRAGMENT, standards.SHADER_RESOURCE_PATH + "ssao/ssao_first_pass.frag", allocator=allocator)
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

    shader_pass = resource.init_shader_program("SSAO second pass")
    shader_pass.shaders[.VERTEX] = vert_id
    shader_pass.shaders[.FRAGMENT] = frag_id

    ok = true
    return
}

generate_ssao_second_pass_frag_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (frag_id: resource.ResourceIdent, ok: bool) {
    return resource.generate_shader(manager, .FRAGMENT, standards.SHADER_RESOURCE_PATH + "ssao/ssao_second_pass.frag", allocator=allocator)
}

// Assumes SSAO for now
make_lighting_passes :: proc(
    window_res: win.WindowResolution,
    background_colour: [4]f32,
    ssao_output: RenderPassIO,
) -> (ok: bool) {

    add_render_passes(
        make_render_pass(
            shader_gather = RenderPassShaderGenerate(LightingShaderGenerateConfig{}),
            mesh_gather = RenderPassQuery{ material_query =
                proc(material: resource.Material, type: resource.MaterialType) -> bool {
                    return type.alpha_mode != .BLEND && !type.double_sided
                }
            },
            properties=RenderPassProperties{
                geometry_z_sorting = .ASC,
                face_culling = FaceCulling.BACK,
                viewport = [4]i32{ 0, 0, window_res.w, window_res.h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = background_colour,
                multisample = true
            },
            outputs = []RenderPassIO {
                {
                    nil,
                    AttachmentID{ .COLOUR, 0 },
                    "OpaqueSingleSidedColour"
                },
                {
                    nil,
                    AttachmentID{ type=.DEPTH },
                    "OpaqueSingleSidedDepth"
                }
            },
            inputs = []RenderPassIO{ ssao_output },
            name = "Opaque Single Sided Pass"
        ) or_return,
    )

    opaque_single_pass := get_render_pass("Opaque Single Sided Pass") or_return
    add_render_passes(
        make_render_pass(
            shader_gather = opaque_single_pass,
            mesh_gather = RenderPassQuery{ material_query =
                proc(material: resource.Material, type: resource.MaterialType) -> bool {
                    return type.alpha_mode != .BLEND && type.double_sided
                }
            },
            properties=RenderPassProperties{
                geometry_z_sorting = .ASC,
                viewport = [4]i32{ 0, 0, window_res.w, window_res.h },
                multisample = true,
                render_skybox = true,  // Rendering skybox will set certain properties indepdendent of what is set in the pass properties, it will also be done last in the pass
            },
            outputs = []RenderPassIO {
                {
                    nil,
                    AttachmentID{ .COLOUR, 0 },
                    "OpaqueDoubleSidedColour"
                },
                {
                    nil,
                    AttachmentID{ type=.DEPTH },
                    "OpaqueDoubleSidedDepth"
                }
            },
            inputs = []RenderPassIO{ ssao_output },
            name = "Opaque Double Sided Pass"
        ) or_return,
        make_render_pass(
            shader_gather = opaque_single_pass,
                mesh_gather = RenderPassQuery{ material_query =
                    proc(material: resource.Material, type: resource.MaterialType) -> bool {
                        return type.alpha_mode == .BLEND
                    }
                },
            properties = RenderPassProperties{
                geometry_z_sorting = .DESC,
                face_culling = FaceCulling.ADAPTIVE,
                viewport = [4]i32{ 0, 0, window_res.w, window_res.h },
                multisample = true,
                blend_func = BlendFunc{ .SOURCE_ALPHA, .ONE_MINUS_SOURCE_ALPHA },
            },
            outputs = []RenderPassIO {
                {
                    nil,
                    AttachmentID{ .COLOUR, 0 },
                    "TransparentColour"
                },
                {
                    nil,
                    AttachmentID{ type = .DEPTH },
                    "TransparentDepth"
                }
            },
            inputs = []RenderPassIO{ ssao_output },
            name = "Transparency Pass"
        ) or_return
    )

    return true
}

@(private)
generate_gbuffer_shader_pass :: proc(
    manager: ^resource.ResourceManager,
    vertex_layout: ^resource.VertexLayout,
    material_type: ^resource.MaterialType,
    options: rawptr,
    allocator: mem.Allocator,
) -> (shader_pass: resource.ShaderProgram, ok: bool) {

    if options == nil {
        dbg.log(.ERROR, "Options is nil in gbuffer generate pass")
        return
    }

    // todo figure out how to hash the gbuffer vertex shader. Previously we hash the vertex layout that contains the shader
    //  todo  , but now we don't have a vertex layout, unless we make vertex layouts and material types index into
    //  todo  the shader store, instead of meshes. This does kind of make sense since the shader store is super simple then, since
    //  todo   not many vertex/material permutations, but lots of meshes

    defines := make([dynamic]string, allocator=allocator); defer delete(defines)
    for attribute in vertex_layout.infos do #partial switch attribute.type {
    case .position: append_elem(&defines, "POSITION_INPUT")
    case .normal: append_elem(&defines, "NORMAL_INPUT")
    case .texcoord: append_elem(&defines, "TEXCOORD_INPUT")
    case .tangent: append_elem(&defines, "TANGENT_INPUT")
    }

    dbg.log(dbg.LogLevel.INFO, "Creating gbuffer vertex shader")
    vert_id := generate_gbuffer_vertex_shader(manager, defines[:], allocator) or_return

    dbg.log(dbg.LogLevel.INFO, "Creating gbuffer fragment shader")
    config := cast(^GBufferShaderGenerateConfig)options
    frag_id := generate_gbuffer_frag_shader(manager, config^, defines[:], allocator) or_return

    // Grabbing shaders here makes it impossible to compile a shader twice
    vert := resource.get_shader(manager, vert_id) or_return
    frag := resource.get_shader(manager, frag_id) or_return

    if vert.id == nil do compile_shader(vert) or_return
    else do dbg.log(.INFO, "Vertex shader already compiled")
    if frag.id == nil do compile_shader(frag) or_return
    else do dbg.log(.INFO, "Fragment shader already compiled")

    shader_pass = resource.init_shader_program("GBuffer shader pass")
    shader_pass.shaders[.VERTEX] = vert_id
    shader_pass.shaders[.FRAGMENT] = frag_id

    // dbg.log(.INFO, "Vert source: %#s", vert.source.string_source)
    // dbg.log(.INFO, "Frag source: %#s", frag.source.string_source)

    ok = true
    return
}

@(private)
generate_lighting_shader_pass :: proc(
    manager: ^resource.ResourceManager,
    vertex_layout: ^resource.VertexLayout,
    material_type: ^resource.MaterialType,
    options: rawptr,
    allocator: mem.Allocator
) -> (shader_pass: resource.ShaderProgram, ok: bool) {

// config := cast(^LightingShaderGenerateConfig)options

    contains_tangent := false
    for info in vertex_layout.infos {
        if info.type == .tangent  {
            contains_tangent = true
            break
        }
    }

    if vertex_layout.shader == nil {
        dbg.log(dbg.LogLevel.INFO, "Creating lighting vertex shader for layout")
        vertex_layout.shader = generate_lighting_vertex_shader(manager, contains_tangent, allocator) or_return
    }
    else do dbg.log(dbg.LogLevel.INFO, "Vertex layout already has shader")

    if material_type.shader == nil {
        dbg.log(dbg.LogLevel.INFO, "Creating lighting fragment shader for material type")
        material_type.shader = generate_lighting_frag_shader(manager, contains_tangent, allocator) or_return
    }
    else do dbg.log(dbg.LogLevel.INFO, "Material type already has shader")

    // Grabbing shaders here makes it impossible to compile a shader twice
    vert := resource.get_shader(manager, vertex_layout.shader.?) or_return
    frag := resource.get_shader(manager, material_type.shader.?) or_return

    if vert.id == nil do compile_shader(vert) or_return
    if frag.id == nil do compile_shader(frag) or_return

    shader_pass = resource.init_shader_program("Lighting pass")
    shader_pass.shaders[.VERTEX] = vertex_layout.shader.?
    shader_pass.shaders[.FRAGMENT] = material_type.shader.?

    ok = true
    return
}

@(private)
generate_lighting_vertex_shader :: proc(
    manager: ^resource.ResourceManager,
    contains_tangent: bool,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    dbg.log(.INFO, "Generating lighting vertex shader")

    defines := contains_tangent ? []string{"CONTAINS_TANGENT"} : {}
    return resource.generate_shader(manager, .VERTEX, standards.SHADER_RESOURCE_PATH + "pbr/pbr.vert", ..defines, allocator=allocator)
}

@(private)
generate_lighting_frag_shader :: proc(
    manager: ^resource.ResourceManager,
    contains_tangent: bool,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    dbg.log(.INFO, "Generating lighting frag shader")

    defines := contains_tangent ? []string{"CONTAINS_TANGENT"} : {}
    return resource.generate_shader(manager, .FRAGMENT, standards.SHADER_RESOURCE_PATH + "pbr/pbr.frag", ..defines, allocator=allocator)
}

@(private)
generate_gbuffer_vertex_shader :: proc(
    manager: ^resource.ResourceManager,
    defines: []string,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    dbg.log(.INFO, "Generating gbuffer vertex shader")
    return resource.generate_shader(manager, .VERTEX, standards.SHADER_RESOURCE_PATH + "gbuffer/gbuffer.vert", ..defines, allocator=allocator)
}

@(private)
generate_gbuffer_frag_shader :: proc(
    manager: ^resource.ResourceManager,
    generate_config: GBufferShaderGenerateConfig,
    defines: []string,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    dbg.log(.INFO, "Generating gbuffer frag shader")
    return resource.generate_shader(manager, .FRAGMENT, standards.SHADER_RESOURCE_PATH + "gbuffer/gbuffer.frag", ..defines, allocator=allocator)
}
