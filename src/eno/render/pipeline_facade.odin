package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../resource"
import "../utils"
import "../standards"

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
    .NORMAL = { gl.RGBA16F, gl.RGBA, gl.FLOAT },
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
                io.identifier = "gbNormal"
                if component == .NORMAL do normal_output = io
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


make_ssao_passes :: proc(w, h: i32, gbuf_output: RenderPassIO, allocator := context.allocator) -> (ssao_colour_output: RenderPassIO, ssao_bn_output: RenderPassIO, ok: bool) {

    framebuffer := make_framebuffer(w, h, allocator)
    bind_framebuffer(framebuffer) or_return

    tex_properties := make(resource.TextureProperties, allocator=allocator)
    defer delete(tex_properties)
    tex_properties[.MIN_FILTER] = .LINEAR
    tex_properties[.MAG_FILTER] = .LINEAR

    ssao_colour_texture := resource.Texture{
        name = fmt.aprintf("SSAO first pass texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_colour_texture.gpu_texture = make_texture(ssao_colour_texture, internal_format=gl.R32F, format=gl.RED, type=gl.FLOAT)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_colour_texture, id = gl.COLOR_ATTACHMENT0, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return

    ssao_bent_normal_texture := resource.Texture{
        name = fmt.aprintf("SSAO bent normal first pass texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_bent_normal_texture.gpu_texture = make_texture(ssao_bent_normal_texture, internal_format=gl.RGB32F, format=gl.RGB, type=gl.FLOAT)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_bent_normal_texture, id = gl.COLOR_ATTACHMENT1, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return

    ssao_blurred_colour_texture := resource.Texture{
        name = fmt.aprintf("SSAO second pass texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_blurred_colour_texture.gpu_texture = make_texture(ssao_blurred_colour_texture, internal_format=gl.R32F, format=gl.RED, type=gl.FLOAT)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_blurred_colour_texture, id = gl.COLOR_ATTACHMENT2, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return

    ssao_blurred_bent_normal_texture := resource.Texture{
        name = fmt.aprintf("SSAO blurred bent normal texture", allocator=allocator),
        image = resource.Image{ w=w, h=h },
        type = .TWO_DIM,
        properties = utils.copy_map(tex_properties, allocator=allocator)
    }
    ssao_blurred_bent_normal_texture.gpu_texture = make_texture(ssao_blurred_bent_normal_texture, internal_format=gl.RGB32F, format=gl.RGB, type=gl.FLOAT)
    framebuffer_add_attachments(&framebuffer, Attachment{ data=ssao_blurred_bent_normal_texture, id = gl.COLOR_ATTACHMENT3, type = .COLOUR })
    check_framebuffer_status(framebuffer) or_return

    attachments, _ := slice.map_keys(framebuffer.attachments, allocator=allocator); defer delete(attachments)
    framebuffer_draw_attachments(framebuffer, ..attachments, allocator=allocator) or_return
    check_framebuffer_status(framebuffer) or_return

    add_framebuffers(framebuffer, allocator=allocator)

    ssao_fbo := Context.pipeline.frame_buffers[len(Context.pipeline.frame_buffers) - 1]
    ssao_colour_output = RenderPassIO {
        ssao_fbo,
        AttachmentID{ .COLOUR, 2 },
        "SSAOBlur"
    }

    ssao_bn_output = RenderPassIO {
        ssao_fbo,
        AttachmentID{ .COLOUR, 3 },
        "SSAOBlurredBentNormal"
    }

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
                    "SSAOColour"
                },
                {
                    ssao_fbo,
                    AttachmentID{ .COLOUR, 1 },
                    "SSAOBentNormal"
                }
            }
        ) or_return,
        make_render_pass(
            shader_gather = generate_ssao_second_shader_pass,
            name = "SSAO second pass",
            frame_buffer = ssao_fbo,
            mesh_gather = SinglePrimitiveMesh{ type=.QUAD },
            properties=RenderPassProperties{
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
                disable_depth_test=true
            },
            inputs = []RenderPassIO{
                  { ssao_fbo, AttachmentID{ type=.COLOUR }, "SSAOColour" },
            },
            outputs = []RenderPassIO { ssao_colour_output }
        ) or_return,
        make_render_pass(
            shader_gather = generate_ssao_second_shader_pass,
            name = "SSAO third pass",
            frame_buffer = ssao_fbo,
            mesh_gather = SinglePrimitiveMesh{ type=.QUAD },
            properties=RenderPassProperties{
                viewport = [4]i32{ 0, 0, w, h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
                disable_depth_test=true
            },
            inputs = []RenderPassIO{
                { ssao_fbo, AttachmentID{ .COLOUR, 1 }, "SSAOColour" },
            },
            outputs = []RenderPassIO { ssao_bn_output }
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

        scale := f32(i) / 64

        kernel[i] = sample * linalg.lerp(f32(0.1), 1.0, scale*scale)
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