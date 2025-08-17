package render

import gl "vendor:OpenGL"

import "../ecs"
import "../resource"
import "../utils"
import dbg "../debug"
import "../standards"
import lutils "../utils/linalg_utils"
import cam "../camera"

import "core:math"
import "core:slice"
import "core:strings"
import "base:runtime"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:log"


RenderContext :: struct {
    camera_ubo: ^ShaderBuffer,
    lights_ssbo: ^ShaderBuffer,
    skybox_comp: ^resource.GLComponent,
    skybox_shader: ^resource.ShaderProgram
}

RENDER_CONTEXT: RenderContext  // Global render context, this is fine really, only stores small amount of persistent external pointing data
// Don't know if I care enough to destroy the render context

@(private)
ModelData :: struct {
    model: ^resource.Model,
    world: ^standards.WorldComponent,
    instance_to: ^resource.InstanceTo,
}

@(private)
MeshData :: struct {
    mesh: ^resource.Mesh,
    world: ^standards.WorldComponent,
    instance_to: ^resource.InstanceTo
}

render :: proc(
    manager: ^resource.ResourceManager,
    pipeline: RenderPipeline,
    scene: ^ecs.Scene,
    allocator := context.allocator,
    temp_allocator := context.temp_allocator
) -> (ok: bool) {
    pipeline := pipeline

    /*
        for later:
            instancing done via InstanceTo ecs component
    */

    if len(pipeline.passes) == 0 {
        dbg.log(.ERROR, "No passes to render")
        return
    }


    // Used for render passes that query their own data
    mesh_data_map := make(map[^RenderPass][dynamic]MeshData, allocator=temp_allocator)
    // Used for render passes which point to another render pass's model data
    mesh_data_references := make(map[^RenderPass]^[dynamic]MeshData, allocator=temp_allocator)

    for &pass in pipeline.passes {

        // Gather model data
        mesh_data: ^[dynamic]MeshData
        switch v in pass.mesh_gather {
            case ^RenderPass:
                if v not_in mesh_data_map {
                    if v not_in mesh_data_references {
                        dbg.log(.ERROR, "Render pass gather points to a render pass which has not yet been assigned model data, please order the render-passes to fix")
                        return
                    }

                    mesh_data = mesh_data_references[v]
                }
                else do mesh_data = &mesh_data_map[v]
                mesh_data_references[&pass] = mesh_data
            case RenderPassQuery:
                // log.info("pass query")
                mesh_data_map[&pass] = query_scene(manager, scene, v, temp_allocator) or_return
                mesh_data = &mesh_data_map[&pass]
            case nil:
                mesh_data_map[&pass] = query_scene(manager, scene, {}, temp_allocator) or_return
                mesh_data = &mesh_data_map[&pass]

        }
        if mesh_data == nil {
            dbg.log(.ERROR, "Mesh data nil")
            return
        }
        if pass.properties.geometry_z_sorting != .NO_SORT do sort_geometry_by_depth(mesh_data[:], pass.properties.geometry_z_sorting == .ASC)

        // Group geometry by shaders
        shader_map := group_meshes_by_shader(pipeline.shader_store, &pass, mesh_data^, temp_allocator) or_return

        handle_pass_properties(pipeline, pass) or_return
        check_framebuffer_status_raw() or_return

        // render meshes
        for shader_pass_id, &mesh_datas in shader_map {
            // dbg.log(.INFO, "Rendering for shader pass")

            shader_pass := resource.get_shader_pass(manager, shader_pass_id) or_return

            attach_program(shader_pass^)
            bind_ibl_uniforms(scene, shader_pass) or_return
            update_camera_ubo(scene) or_return
            update_lights_ssbo(scene) or_return

            for &mesh_data in mesh_datas {
                // dbg.log(.INFO, "Rendering mesh data")
                model_mat, normal_mat := model_and_normal(mesh_data.mesh, mesh_data.world, scene.viewpoint)
                transfer_mesh(manager, mesh_data.mesh) or_return

                bind_material_uniforms(manager, mesh_data.mesh.material, shader_pass) or_return
                resource.set_uniform(shader_pass, standards.MODEL_MAT, model_mat)
                resource.set_uniform(shader_pass, standards.NORMAL_MAT, normal_mat)

                issue_single_element_draw_call(mesh_data.mesh.indices_count)
            }
        }

        if pass.properties.render_skybox do render_skybox(manager, scene, allocator) or_return
    }


    return true
}

// Allocator is perm content, not temp
@(private)
render_skybox :: proc(manager: ^resource.ResourceManager, scene: ^ecs.Scene, allocator := context.allocator) -> (ok: bool) {
    if scene.image_environment == nil {
        dbg.log(.ERROR, "Scene image environment must be available to render skybox")
        return
    }

    env := scene.image_environment.?
    if env.environment_map == nil {
        dbg.log(.ERROR, "Scene image environment map must be avaiable to render skybox")
        return
    }
    // dbg.log(.INFO, "Rendering skybox")
    env_map := env.environment_map.?
    if env_map.gpu_texture == nil {
        dbg.log(.ERROR, "Environment cubemap gpu texture is not provided")
        return
    }

    if RENDER_CONTEXT.skybox_comp == nil {
        RENDER_CONTEXT.skybox_comp = new(resource.GLComponent)
        RENDER_CONTEXT.skybox_comp^ = create_primitive_cube()
    }

    if RENDER_CONTEXT.skybox_comp.vao == nil {
        dbg.log(.ERROR, "Vertex array nil is unexpected in skybox render")
        return
    }

    if RENDER_CONTEXT.skybox_shader == nil {
        RENDER_CONTEXT.skybox_shader = new(resource.ShaderProgram)
        RENDER_CONTEXT.skybox_shader^ = create_skybox_shader(manager, allocator) or_return
    }

    attach_program(RENDER_CONTEXT.skybox_shader^) or_return

    view := glm.mat4(glm.mat3(scene.viewpoint.look_at))
    resource.set_uniform(RENDER_CONTEXT.skybox_shader, VIEW_MATRIX_UNIFORM, view)
    resource.set_uniform(RENDER_CONTEXT.skybox_shader, PROJECTION_MATRIX_UNIFORM, scene.viewpoint.perspective)

    irr := env.irradiance_map.?
    spec := env.prefilter_map.?
    // bind_texture(0, irr.gpu_texture.?, .CUBEMAP)
    // bind_texture(0, spec.gpu_texture.?, .CUBEMAP)
    bind_texture(0, env_map.gpu_texture.?, .CUBEMAP)
    resource.set_uniform(RENDER_CONTEXT.skybox_shader, ENV_MAP_UNIFORM, i32(0))

    set_face_culling(false)
    render_primitive_cube(RENDER_CONTEXT.skybox_comp.vao.?)

    return true
}

@(private)
create_skybox_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (shader: resource.ShaderProgram, ok: bool) {
    vert := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "skybox.vert", .VERTEX) or_return
    frag := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "skybox.frag", .FRAGMENT) or_return
    shader = resource.make_shader_program(manager, []resource.Shader{ vert, frag }, allocator) or_return
    transfer_shader_program(manager, &shader) or_return

    ok = true
    return
}

@(private)
bind_ibl_uniforms :: proc(scene: ^ecs.Scene, shader: ^resource.ShaderProgram) -> (ok: bool) {
    m_env := scene.image_environment
    if m_env == nil {
        dbg.log(.ERROR, "Scene image environment for ibl not yet setup")
        return
    }

    env := m_env.?
    if env.environment_map == nil || env.brdf_lookup == nil || env.irradiance_map == nil || env.prefilter_map == nil {
        dbg.log(.ERROR, "Not all IBL textures/cubemaps are available")
        return
    }
    irradiance_map := env.irradiance_map.?
    prefilter_map := env.prefilter_map.?
    brdf_lut := env.brdf_lookup.?

    // log.infof("%#v %#v %#v", irradiance_map, prefilter_map, brdf_lut)

    texture_unit: i32
    texture_unit = i32(PBRSamplerBindingLocation.IRRADIANCE_MAP)
    bind_texture(texture_unit, irradiance_map.gpu_texture, irradiance_map.type) or_return
    resource.set_uniform(shader, "irradianceMap", texture_unit)

    texture_unit = i32(PBRSamplerBindingLocation.BRDF_LUT)
    bind_texture(texture_unit, brdf_lut.gpu_texture, brdf_lut.type) or_return
    resource.set_uniform(shader, "brdfLUT", texture_unit)

    texture_unit = i32(PBRSamplerBindingLocation.PREFILTER_MAP)
    bind_texture(texture_unit, prefilter_map.gpu_texture, prefilter_map.type) or_return
    resource.set_uniform(shader, "prefilterMap", texture_unit)

    ok = true
    return
}

@(private)
group_meshes_by_shader :: proc(
    shader_store: RenderShaderStore,
    render_pass: ^RenderPass,
    meshes: [dynamic]MeshData,
    temp_allocator := context.temp_allocator
) -> (shader_map: map[resource.ResourceIdent][dynamic]MeshData, ok: bool) {

    // Get shader mapping from RenderShaderStore
    shader_mapping: ^RenderShaderMapping
    switch gather in render_pass.shader_gather {
        case ^RenderPass:
            switch inner_gather in gather.shader_gather {
                case ^RenderPass:
                    dbg.log(.ERROR, "If a render pass shader gather points to another render pass, that other render pass must not point to another pass")
                    return
                case RenderPassShaderGenerate:
                    if gather not_in shader_store.render_pass_mappings {
                        dbg.log(.ERROR, "Inner render pass not gathered data yet, please sort render passes by gathers")
                        return
                    }
                    shader_mapping = &shader_store.render_pass_mappings[gather]
            }
        case RenderPassShaderGenerate:
            shader_mapping = &shader_store.render_pass_mappings[render_pass]

    }

    shader_map = make(map[resource.ResourceIdent][dynamic]MeshData, allocator=temp_allocator)

    for &mesh_data in meshes {
        if mesh_data.mesh.mesh_id == nil {
            dbg.log(.ERROR, "Shader pass not generated for mesh: %#v", mesh_data.mesh.material)
            return
        }

        shader_id := shader_mapping[mesh_data.mesh.mesh_id.?]

        pair := MeshData{ mesh_data.mesh, mesh_data.world, mesh_data.instance_to}
        if shader_id in shader_map {
            dyn := &shader_map[shader_id]
            append(dyn, pair)
        }
        else {
            dyn := make([dynamic]MeshData, 1, temp_allocator)
            dyn[0] = pair
            shader_map[shader_id] = dyn
        }

    }

    ok = true
    return
}


// Handles binding of framebuffer along with enabling of certain settings/tests
@(private)
handle_pass_properties :: proc(pipeline: RenderPipeline, pass: RenderPass) -> (ok: bool) {
    if pass.frame_buffer == nil {
        bind_default_framebuffer()
        if pass.properties.viewport == nil {
            dbg.log(.ERROR, "Viewport must be set if not specifying a framebuffer")
            return
        }
        viewport := pass.properties.viewport.?
        set_render_viewport(viewport[0], viewport[1], viewport[2], viewport[3])
    }
    else {
        frame_buffer := utils.safe_index(pipeline.frame_buffers, pass.frame_buffer.?) or_return
        bind_framebuffer(frame_buffer^) or_return
        if pass.properties.viewport != nil {
            viewport := pass.properties.viewport.?
            set_render_viewport(viewport[0], viewport[1], viewport[2], viewport[3])
        }
        else do set_render_viewport(0, 0, frame_buffer.w, frame_buffer.h)
    }

    properties := pass.properties
    set_front_face(properties.front_face)

    set_depth_test(!properties.disable_depth_test)
    set_stencil_test(properties.stencil_test)

    masks := properties.masks
    enable_colour_writes(
        .DISABLE_COL_R not_in masks,
        .DISABLE_COL_G not_in masks,
        .DISABLE_COL_B not_in masks,
        .DISABLE_COL_A not_in masks,
    )

    enable_depth_writes(.DISABLE_DEPTH not_in masks)
    enable_stencil_wrties(.ENABLE_STENCIL in masks)

    if properties.blend_func != nil {
        set_blend(true)
        set_blend_func(properties.blend_func.?)
    }
    else {
        set_blend(false)
        set_default_blend_func()
    }

    if properties.face_culling != nil {
        cull_geometry_faces(properties.face_culling.?)
    }
    else do set_face_culling(false)

    if properties.polygon_mode != nil {
        set_polygon_mode(properties.polygon_mode.?)
    }
    else do set_default_polygon_mode()

    set_multisampling(properties.multisample)


    clear_mask(properties.clear)

    return true
}


@(private)
sort_geometry_by_depth :: proc(meshes_data: []MeshData, z_asc: bool) {
    mesh_pos :: proc(mesh_data: MeshData) -> [3]f32 {
        return mesh_data.world.position + mesh_data.world.scale * mesh_data.mesh.centroid;
    }
    sort_proc := z_asc ? proc(a: MeshData, b: MeshData) -> bool {
        return mesh_pos(a).z < mesh_pos(b).z
    } : proc(a: MeshData, b: MeshData) -> bool {
        return mesh_pos(a).z > mesh_pos(b).z
    }
    slice.sort_by(meshes_data, sort_proc)
}


@(private)
query_scene :: proc(
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    pass_query: RenderPassQuery,
    temp_allocator: mem.Allocator
) -> (mesh_data: [dynamic]MeshData, ok: bool) {
    // log.infof("querying with pass query")

    // todo handle pass_query (nil case as well)

    isVisibleQueryData := true
    component_queries := make([dynamic]ecs.ComponentQuery, allocator=temp_allocator)
    append_elems(&component_queries, ..[]ecs.ComponentQuery{
        { label = resource.MODEL_COMPONENT.label, action = .QUERY_AND_INCLUDE },
        { label = standards.WORLD_COMPONENT.label, action = .QUERY_AND_INCLUDE },
        { label = resource.INSTANCE_TO_COMPONENT.label, action = .NO_QUERY_BUT_INCLUDE },
        { label = standards.VISIBLE_COMPONENT.label, action = .QUERY_NO_INCLUDE, data = &isVisibleQueryData }
    })

    for query in pass_query.component_queries {
        append(&component_queries, ecs.ComponentQuery{ query.label, .QUERY_NO_INCLUDE, query.data })
    }

    query := ecs.ArchetypeQuery{ components = component_queries[:]}
    query_result := ecs.query_scene(scene, query, allocator=temp_allocator) or_return

    // flatten into lots of meshes
    ModelWorldPair :: struct {
        model: ^resource.Model,
        world_comp: ^standards.WorldComponent
    }
    model_data := make(#soa[dynamic]ModelData, temp_allocator)

    for _, arch_result in query_result {
        models, models_ok := ecs.get_component_from_arch_result(arch_result, resource.Model, resource.MODEL_COMPONENT.label, temp_allocator)
        if !models_ok {
            dbg.log(.ERROR, "Models not returned from query")
            return
        }

        worlds, worlds_ok := ecs.get_component_from_arch_result(arch_result, standards.WorldComponent, standards.WORLD_COMPONENT.label, temp_allocator)
        if !worlds_ok {
            dbg.log(.ERROR, "World components not returned from query")
            return
        }

        if len(models) != len(worlds) {
            dbg.log(.ERROR, "Received unbalanced input from scene query")
            return
        }

        instance_tos, instance_tos_ok := ecs.get_component_from_arch_result(arch_result, resource.InstanceTo, resource.INSTANCE_TO_COMPONENT.label, temp_allocator)

        if instance_tos_ok do for i in 0..<len(models) {
            append(&model_data, ModelData{ models[i], worlds[i], instance_tos[i] })
        }
        else do for i in 0..<len(models) {
            append(&model_data, ModelData{ models[i], worlds[i], nil })
        }

    }

    models, worlds, instance_tos := soa_unzip(model_data[:])  // this unzip is a bit obtuse
    mesh_data = make([dynamic]MeshData, allocator=temp_allocator)
    for meshes, i in utils.extract_field(models, "meshes", [dynamic]resource.Mesh, allocator=temp_allocator) {
        for &mesh in meshes {
            material_type := resource.get_material(manager, mesh.material.type) or_return
            if pass_query.material_query == nil || pass_query.material_query.?(mesh.material, material_type^) {
                append(&mesh_data, MeshData{ &mesh, worlds[i], instance_tos[i] })
            }
        }
    }

    ok = true
    return
}


apply_billboard_rotation :: proc(cam_position: glm.vec3, world: standards.WorldComponent, cylindrical := true) -> standards.WorldComponent {
     start := glm.vec3{ 0.0, 0.0, -1.0 }
    // start := glm.normalize(world.position)
     dest := glm.normalize(cam_position - world.position)
    // dest := glm.normalize(cam_position)

    if cylindrical do dest.y = 0.0
    dot := glm.dot(start, dest)
    angle := glm.acos(dot)

    if dot > 0.999 {
        return { world.position, world.scale, 1.0 }
    }
    else if dot < -0.999 {
        axis := glm.vec3{ 0.0, 1.0, 0.0 }
        quat := glm.quatAxisAngle(glm.normalize(glm.cross(start, axis)), glm.PI)
        return { world.position, world.scale, quat }
    }

    axis := glm.normalize(glm.cross(start, dest))

    return { world.position, world.scale, glm.quatAxisAngle(axis, angle) }
    /*
    world := world
    xyz := glm.cross(start, dest)
    world.rotation.x = xyz.x
    world.rotation.y = xyz.y
    world.rotation.z = xyz.z
    world.rotation.w = glm.sqrt((glm.pow(glm.length(start), 2) * glm.pow(glm.length(dest), 2))) + glm.dot(start, dest)
    return world
    */
}

model_and_normal :: proc(mesh: ^resource.Mesh, world: ^standards.WorldComponent, cam: ^cam.Camera) -> (model: glm.mat4, normal: glm.mat3) {
    world_comp := mesh.is_billboard ? apply_billboard_rotation(cam.position, world^) : world^
    model = standards.model_from_world_component(world_comp, mesh.transpose_transformation)
    normal = lutils.normal_mat(model)
    return
}

// Cannot use material infos from Material struct because some textures are
//  not available even if the specific mat property is used
// I've made this pascal case for some reason
MAX_MATERIAL_USAGE :: u32  // Must be reflected as the same type in any shaders
MaterialUsage :: enum {
    PBRMetallicRoughnessTexture,
    BaseColourTexture,
    EmissiveTexture,
    OcclusionTexture,
    NormalTexture,
    ClearcoatTexture,
    ClearcoatRoughnessTexture,
    ClearcoatNormalTexture
}

// Arbitrary, PBR shaders defining materials must match these sampler binding locations
PBRSamplerBindingLocation :: enum u32 {
    BASE_COLOUR,
    EMISSIVE,
    OCCLUSION,
    NORMAL,
    PBR_METALLIC_ROUGHNESS,
    CLEARCOAT,
    CLEARCOAT_ROUGHNESS,
    CLEARCOAT_NORMAL,
    BRDF_LUT,
    IRRADIANCE_MAP,
    PREFILTER_MAP
}

@(private)
bind_material_uniforms :: proc(manager: ^resource.ResourceManager, material: resource.Material, lighting_shader: ^resource.ShaderProgram) -> (ok: bool) {
    type := resource.get_material(manager, material.type) or_return
    resource.set_uniform(lighting_shader, resource.ALPHA_CUTOFF, type.alpha_cutoff)
    resource.set_uniform(lighting_shader, resource.ENABLE_ALPHA_CUTOFF, i32(type.alpha_mode == .MASK))

    usages: bit_set[MaterialUsage; MAX_MATERIAL_USAGE]
    for info, property in material.properties {
        switch v in property.value {
            case resource.PBRMetallicRoughness:
                if v.base_colour != nil {
                    usages += { .BaseColourTexture}
                    base_colour := resource.get_texture(manager, v.base_colour) or_return
                    texture_unit := i32(PBRSamplerBindingLocation.BASE_COLOUR)

                    transfer_texture(base_colour)
                    bind_texture(texture_unit, base_colour.gpu_texture) or_return
                    resource.set_uniform(lighting_shader, resource.BASE_COLOUR_TEXTURE, texture_unit)
                }

                if v.metallic_roughness != nil {
                    usages += { .PBRMetallicRoughnessTexture }
                    metallic_roughness := resource.get_texture(manager, v.metallic_roughness) or_return
                    texture_unit := i32(PBRSamplerBindingLocation.PBR_METALLIC_ROUGHNESS)

                    transfer_texture(metallic_roughness)
                    bind_texture(texture_unit, metallic_roughness.gpu_texture) or_return
                    resource.set_uniform(lighting_shader, resource.PBR_METALLIC_ROUGHNESS, texture_unit)
                }

                resource.set_uniform(lighting_shader, resource.BASE_COLOUR_FACTOR, v.base_colour_factor[0], v.base_colour_factor[1], v.base_colour_factor[2], v.base_colour_factor[3])
                resource.set_uniform(lighting_shader, resource.METALLIC_FACTOR, v.metallic_factor)
                resource.set_uniform(lighting_shader, resource.ROUGHNESS_FACTOR, v.roughness_factor)

            case resource.EmissiveFactor:
                // No usage, bundled within EmissiveTexture..
                resource.set_uniform(lighting_shader, resource.EMISSIVE_FACTOR, v[0], v[1], v[2])

            case resource.EmissiveTexture:
                usages += { .EmissiveTexture }
                emissive_texture := resource.get_texture(manager, resource.ResourceIdent(v)) or_return
                texture_unit := i32(PBRSamplerBindingLocation.EMISSIVE)

                transfer_texture(emissive_texture)
                bind_texture(texture_unit, emissive_texture.gpu_texture.?) or_return
                resource.set_uniform(lighting_shader, resource.EMISSIVE_TEXTURE, texture_unit)

            case resource.OcclusionTexture:
                usages += { .OcclusionTexture }
                occlusion_texture := resource.get_texture(manager, resource.ResourceIdent(v)) or_return
                texture_unit := i32(PBRSamplerBindingLocation.OCCLUSION)

                transfer_texture(occlusion_texture)
                bind_texture(texture_unit, occlusion_texture.gpu_texture.?) or_return
                resource.set_uniform(lighting_shader, resource.OCCLUSION_TEXTURE, texture_unit)

            case resource.NormalTexture:
                usages += { .NormalTexture }
                normal_texture := resource.get_texture(manager, resource.ResourceIdent(v)) or_return
                texture_unit := i32(PBRSamplerBindingLocation.NORMAL)

                transfer_texture(normal_texture)
                bind_texture(texture_unit, normal_texture.gpu_texture.?) or_return
                resource.set_uniform(lighting_shader, resource.NORMAL_TEXTURE, texture_unit)
            case resource.Clearcoat:
                if v.clearcoat_texture != nil {
                    usages += { .ClearcoatTexture}
                    clearcoat := resource.get_texture(manager, v.clearcoat_texture) or_return
                    texture_unit := i32(PBRSamplerBindingLocation.CLEARCOAT)

                    transfer_texture(clearcoat)
                    bind_texture(texture_unit, clearcoat.gpu_texture) or_return
                    resource.set_uniform(lighting_shader, resource.CLEARCOAT_TEXTURE, texture_unit)
                }

                if v.clearcoat_roughness_texture != nil {
                    usages += { .ClearcoatRoughnessTexture }
                    clearcoat_roughness := resource.get_texture(manager, v.clearcoat_roughness_texture) or_return
                    texture_unit := i32(PBRSamplerBindingLocation.CLEARCOAT_ROUGHNESS)

                    transfer_texture(clearcoat_roughness)
                    bind_texture(texture_unit, clearcoat_roughness.gpu_texture) or_return
                    resource.set_uniform(lighting_shader, resource.CLEARCOAT_ROUGHNESS_TEXTURE, texture_unit)
                }

                if v.clearcoat_normal_texture != nil {
                    usages += { .ClearcoatNormalTexture }
                    clearcoat_normal := resource.get_texture(manager, v.clearcoat_normal_texture) or_return
                    texture_unit := i32(PBRSamplerBindingLocation.CLEARCOAT_NORMAL)

                    transfer_texture(clearcoat_normal)
                    bind_texture(texture_unit, clearcoat_normal.gpu_texture) or_return
                    resource.set_uniform(lighting_shader, resource.CLEARCOAT_ROUGHNESS_TEXTURE, texture_unit)
                }

                resource.set_uniform(lighting_shader, resource.CLEARCOAT_FACTOR, v.clearcoat_factor)
                resource.set_uniform(lighting_shader, resource.CLEARCOAT_ROUGHNESS_FACTOR, v.clearcoat_roughness_factor)
        }
    }

    resource.set_uniform(lighting_shader, resource.MATERIAL_USAGES, transmute(MAX_MATERIAL_USAGE)usages)
    return true
}


CameraBufferData :: struct #packed {
    position: glm.vec3,
    _pad: f32,
    view: glm.mat4,
    projection: glm.mat4
}

update_camera_ubo :: proc(scene: ^ecs.Scene) -> (ok: bool) {
    dbg.log()

    viewpoint := scene.viewpoint
    if viewpoint == nil {
        dbg.log(dbg.LogLevel.ERROR, "Scene viewpoint is nil!")
        return
    }

    camera_buffer_data := CameraBufferData {
        viewpoint.position,
        0,
        cam.camera_look_at(viewpoint),
        cam.get_perspective(viewpoint)
    }

    if RENDER_CONTEXT.camera_ubo == nil {
        RENDER_CONTEXT.camera_ubo = new(ShaderBuffer)
        RENDER_CONTEXT.camera_ubo^ = make_shader_buffer(&camera_buffer_data, size_of(CameraBufferData), .UBO, 0, { .WRITE_MANY_READ_MANY, .DRAW })
    }
    else {
        ubo := RENDER_CONTEXT.camera_ubo
        transfer_buffer_data(ShaderBufferType.UBO, &camera_buffer_data, size_of(CameraBufferData), update=true, buffer_id=ubo.id.?)
    }

    return true
}

GPULightInformation :: struct #packed {
    colour: [3]f32,
    _pad: f32,
    position: [3]f32,
    intensity: f32
}

SpotLightGPU :: struct #packed {
    light_information: GPULightInformation,
    direction: [3]f32,
    inner_cone_angle: f32,
    outer_cone_angle: f32,
    _pad: [3]f32,
}

DirectionalLightGPU :: struct #packed {
    light_information: GPULightInformation,
    direction: [3]f32,
    _pad: f32
}

PointLightGPU :: struct #packed {
    light_information: GPULightInformation
}

conv_light_information :: proc(info: resource.LightSourceInformation) -> GPULightInformation {
    return { info.colour, 0.0, info.position, info.intensity }
}

// Returns heap allocated gpu light - make sure to free
light_to_gpu_light :: proc(light: resource.Light) -> (gpu_light: rawptr) {

    switch v in light {
        case resource.SpotLight:
            p_Light := new(SpotLightGPU)
            p_Light^ = SpotLightGPU{
                light_information = conv_light_information(v.light_information),
                direction = v.direction,
                inner_cone_angle = v.inner_cone_angle,
                outer_cone_angle = v.outer_cone_angle
            }
            gpu_light = p_Light
        case resource.PointLight:
            p_Light := new(PointLightGPU)
            p_Light^ = PointLightGPU{ conv_light_information(v) }
            gpu_light = p_Light
        case resource.DirectionalLight:
            p_Light := new(DirectionalLightGPU)
            p_Light^ = DirectionalLightGPU{
                light_information = conv_light_information(v.light_information),
                direction = v.direction
            }
            gpu_light = p_Light
    }

    if gpu_light == nil do dbg.log(dbg.LogLevel.ERROR, "Nil GPU light information found")
    return
}


update_lights_ssbo :: proc(scene: ^ecs.Scene) -> (ok: bool) {
    // Query to return only light components
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = resource.LIGHT_COMPONENT.label, action = .QUERY_AND_INCLUDE }
    }}
    query_result := ecs.query_scene(scene, query) or_return

    lights := ecs.get_component_from_query_result(query_result, resource.Light, resource.LIGHT_COMPONENT.label) or_return

    spot_lights := make([dynamic]^resource.SpotLight)
    directional_lights := make([dynamic]^resource.DirectionalLight)
    point_lights := make([dynamic]^resource.PointLight)

    for &light in lights do switch &v in light {
        case resource.SpotLight: if v.light_information.enabled do append(&spot_lights, &v)
        case resource.DirectionalLight: if v.light_information.enabled do append(&directional_lights, &v)
        case resource.PointLight: if v.enabled do append(&point_lights, &v)
    }

    num_spot_lights: uint = len(spot_lights)
    num_directional_lights: uint = len(directional_lights)
    num_point_lights: uint = len(point_lights)

    SPOT_LIGHT_GPU_SIZE :: size_of(SpotLightGPU)
    DIRECTIONAL_LIGHT_GPU_SIZE :: size_of(DirectionalLightGPU)
    POINT_LIGHT_GPU_SIZE :: size_of(PointLightGPU)

    spot_light_buffer_size := SPOT_LIGHT_GPU_SIZE * num_spot_lights
    directional_light_buffer_size := DIRECTIONAL_LIGHT_GPU_SIZE * num_directional_lights
    point_light_buffer_size := POINT_LIGHT_GPU_SIZE * num_point_lights

    light_ssbo_data: []byte = make([]byte, 32 /* For counts and pad */ + spot_light_buffer_size + directional_light_buffer_size + point_light_buffer_size)
    (transmute(^uint)&light_ssbo_data[0])^ = num_spot_lights
    (transmute(^uint)&light_ssbo_data[4])^ = num_directional_lights
    (transmute(^uint)&light_ssbo_data[8])^ = num_point_lights

    current_offset := 16
    for light in spot_lights {
        gpu_light := light_to_gpu_light(light^)
        defer free(gpu_light)
        mem.copy(&light_ssbo_data[current_offset], gpu_light, SPOT_LIGHT_GPU_SIZE)
        current_offset += SPOT_LIGHT_GPU_SIZE
    }

    for light in directional_lights {
        gpu_light := light_to_gpu_light(light^)
        defer free(gpu_light)
        mem.copy(&light_ssbo_data[current_offset], gpu_light, DIRECTIONAL_LIGHT_GPU_SIZE)
        current_offset += DIRECTIONAL_LIGHT_GPU_SIZE
    }

    for light in point_lights {
        gpu_light := light_to_gpu_light(light^)
        defer free(gpu_light)
        mem.copy(&light_ssbo_data[current_offset], gpu_light, POINT_LIGHT_GPU_SIZE)
        current_offset += POINT_LIGHT_GPU_SIZE
    }

    if RENDER_CONTEXT.lights_ssbo == nil {
        RENDER_CONTEXT.lights_ssbo = new(ShaderBuffer)
        RENDER_CONTEXT.lights_ssbo^ = make_shader_buffer(raw_data(light_ssbo_data), len(light_ssbo_data), .SSBO, 1, { .WRITE_MANY_READ_MANY, .DRAW })
    }
    else {
        ssbo := RENDER_CONTEXT.lights_ssbo
        transfer_buffer_data(ShaderBufferType.UBO, raw_data(light_ssbo_data), len(light_ssbo_data), update=true, buffer_id=ssbo.id.?)
    }

    return true
}





LightingModel :: enum {
    DIRECT
}

MaterialModel :: enum {
    BLING_PHONG,
    PBR
}

/*
    Creates a lighting shader based on vertex attribute info, a material, a lighting model and a material model
    todo unfinished
*/
create_forward_lighting_shader :: proc(
    attribute_infos: resource.VertexLayout,
    material: resource.Material,
    lighting_model: LightingModel,
    material_model: MaterialModel,
    allocator := context.allocator
) -> (vertex: resource.ShaderInfo, frag: resource.ShaderInfo, ok: bool) {

/*

// Add input bindings
shader_layout_from_mesh_layout(&vertex, attribute_infos) or_return

//Lights
light_struct := resource.make_shader_struct("Light",
    { resource.GLSLDataType.vec3, "colour", }, { resource.GLSLDataType.vec3, "position" }
)
resource.add_structs(&frag, light_struct)

resource.add_bindings_of_type(&frag, .SSBO, {
    "lights",
    []resource.ExtendedGLSLPair{
        {
            resource.GLSLVariableArray { "Light" },
            "lights"
        }
    }
})


vertex_source := make([dynamic]string)
defer resource.destroy_function_source(vertex_source[:])

// Add shader input/output for both vertex and fragment
for attribute_info in attribute_infos {
    input_pair := resource.GLSLPair{ glsl_type_from_attribute(attribute_info) or_return, attribute_info.name}
    resource.add_outputs(&vertex, input_pair)
    resource.add_inputs(&frag, input_pair)

    assign_to: string
    defer delete(assign_to)

    if type, type_ok := input_pair.type.(resource.GLSLDataType); type_ok {
        // todo change usage of "position" and "normal" and make a standard for model loading and attribute names, with custom names as well
        if input_pair.name == "position" && type == .vec3 {
            // todo pass this into glsl_type_from_attribute
            prefixed_name := utils.concat("a_", input_pair.name); defer delete(prefixed_name)
            assign_to = fmt.aprintf("vec3(%s * vec4(%s, 1.0))", MODEL_MATRIX_UNIFORM, prefixed_name)
        }
        else if input_pair.name == "normal" && type == .vec3 {
            prefixed_name := utils.concat("a_", input_pair.name); defer delete(prefixed_name)
            assign_to = fmt.aprintf("%s * %s", NORMAL_MATRIX_UNIFORM, prefixed_name)
        }
    }
    if assign_to == "" do assign_to = strings.clone(attribute_info.name)

    utils.fmt_append(&vertex_source, "%s = %s;", input_pair.name, assign_to)
}

// Add vertex MVP uniforms
resource.add_uniforms(&vertex,
    { .mat4, MODEL_MATRIX_UNIFORM },
    { .mat4, VIEW_MATRIX_UNIFORM },
    { .mat4, PROJECTION_MATRIX_UNIFORM },
    { .mat4, NORMAL_MATRIX_UNIFORM }
)

// Add vertex main function
utils.fmt_append(&vertex_source, "gl_Position = %s * %s * vec4(%s, 1.0);", PROJECTION_MATRIX_UNIFORM, VIEW_MATRIX_UNIFORM, "position")

main_func := resource.make_shader_function(.void, "main", vertex_source[:])
resource.add_functions(&vertex, main_func)

// Frag uniforms
if .NORMAL_TEXTURE not_in material.properties {
    dbg.debug_point(dbg.LogLevel.ERROR, "Normal map must be available in the material for lighting")
    return
}

if .PBR_METALLIC_ROUGHNESS not_in material.properties {
    dbg.debug_point(dbg.LogLevel.ERROR, "PBR Metallic Roughness map must be available in the material for lighting")
    return
}

uniforms := make([dynamic]resource.GLSLPair); defer resource.destroy_glsl_pairs(uniforms[:])

// todo
append(&uniforms, resource.GLSLPair{ resource.GLSLDataType.sampler2D, resource.BASE_COLOUR_TEXTURE })  // base colour comes from pbrMetallicRoughness
append(&uniforms, resource.GLSLPair{ resource.GLSLDataType.sampler2D, resource.PBR_METALLIC_ROUGHNESS })
append(&uniforms, resource.GLSLPair{ resource.GLSLDataType.sampler2D, resource.NORMAL_TEXTURE })

inc_emissive_texture := .EMISSIVE_TEXTURE in material.properties
inc_occlusion_texture := .OCCLUSION_TEXTURE in material.properties

if inc_emissive_texture {
    append(&uniforms, resource.GLSLPair{ resource.GLSLDataType.sampler2D, resource.EMISSIVE_TEXTURE })
    append(&uniforms, resource.GLSLPair{ resource.GLSLDataType.vec3, resource.EMISSIVE_FACTOR })
}

if inc_occlusion_texture do append(&uniforms, resource.GLSLPair{ resource.GLSLDataType.sampler2D, resource.OCCLUSION_TEXTURE })

*/


    ok = true
    return
}

MODEL_MATRIX_UNIFORM :: "m_Model"
VIEW_MATRIX_UNIFORM :: "m_View"
PROJECTION_MATRIX_UNIFORM :: "m_Projection"
ENV_MAP_UNIFORM :: "environmentMap"



RenderShaderStore :: struct {
    // Index map to render pass, then MeshStoreID map to shader pass
    // MeshStoreIDs are unique across all render pass mappings
    // or just use a MeshID? We are just pointing to a resource.ResourceID
    // Where does shader dynamic generation occur?
    // Is it only for the typical lighting pass?
    // Should a render pass have a type?
    // If a render pass has a type it means we can match against it and generate the right shaders
    // if not, how do we describe how to generate the shaders in the render pass structure?
    // Solution: Mix
    // Give render passes a "purpose" type, seperate from the properties
    // Purposes:
    // Depth only
    // Lighting pass
    // ... Could be related to AO, AA or anything
    // Then in the shader generation step, populate the RenderShaderStore using Render passes, meshes, the purpose type
    //  giving MeshIDs to meshes in series
    // How to make multiple meshes point to the same Shader Pass? This is very bound to happen
    // Of course we have hashed resource management, this means we can share a ShaderPass if the underlying shaders are the same
    // todo check the hashing to see if this actually works, now I think it will just do a pointer comparison
    // We leverage the resource manager such that after all vertex layout and material shaders are compiled, we go through
    //  all the meshes, create a shader pass, and add it to the manager getting a shared ResourceIdent
    // This shared ResourceIdent will be linked to the mesh in render_pass_mappings
    // This means multiple meshes will use the same ResourceID, this is completely fine

    // What about extendibiliy? What about if a mesh should be added/removed?
    // Then just do the same thing
    // The shader generator procdure just take a ^RenderShaderStore, and do the same as all meshes have done before
    // With another. smaller probably, mesh slice
    // If the vertex-material permutation exists, then no compilation needs to be done
    // If not, then it would need to compile
    // If this is a problem long term, a seperate procedure can be written to populate all needed vertex-material permutations before first frame

    last_mesh_id: resource.MeshIdent,
    // Indexed for each render pass, if union is int then index render_pass_mappings again
    render_pass_mappings: map[^RenderPass]RenderShaderMapping
}

init_shader_store :: proc(allocator := context.allocator) -> (shader_store: RenderShaderStore) {
    shader_store.render_pass_mappings = make(map[^RenderPass]RenderShaderMapping, allocator)
    return
}

destroy_shader_store :: proc(manager: ^resource.ResourceManager, shader_store: RenderShaderStore) -> (ok: bool) {
    ok = true
    for _, mapping in shader_store.render_pass_mappings {
        for _, shader_pass in mapping do ok &= resource.remove_shader_pass(manager, shader_pass)
        delete(mapping)
    }
    delete(shader_store.render_pass_mappings)
    return
}


RenderShaderMapping :: map[resource.MeshIdent]resource.ResourceIdent

populate_all_shaders :: proc(
    pipeline: ^RenderPipeline,
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    allocator := context.allocator,
    temp_allocator := context.temp_allocator
) -> (ok: bool) {
    isVisibleQueryData := true
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = resource.MODEL_COMPONENT.label, action = .QUERY_AND_INCLUDE },
        { label = standards.VISIBLE_COMPONENT.label, action = .QUERY_NO_INCLUDE, data = &isVisibleQueryData }
    }}
    query_result := ecs.query_scene(scene, query, temp_allocator) or_return

    models := ecs.get_component_from_query_result(query_result, resource.Model, resource.MODEL_COMPONENT.label, temp_allocator) or_return

    meshes := make([dynamic]^resource.Mesh, temp_allocator)
    for model_meshes, i in utils.extract_field(models, "meshes", [dynamic]resource.Mesh, allocator=temp_allocator) {
        for &mesh in model_meshes do append(&meshes, &mesh)
    }

    for &pass in pipeline.passes do populate_shaders(&pipeline.shader_store, manager, &pass, meshes[:], allocator) or_return

    ok = true
    return
}

// Call when you have new meshes to populate shader_store and manager with
// todo see if unique field should be a mesh thing rather than a vertex layout/material type thing
// todo -  currently not doing anything with the field
populate_shaders :: proc(
    shader_store: ^RenderShaderStore,
    manager: ^resource.ResourceManager,
    render_pass: ^RenderPass,
    meshes: []^resource.Mesh,
    allocator := context.allocator
) -> (ok: bool) {

    shader_generate_type, do_generate := render_pass.shader_gather.(RenderPassShaderGenerate)
    if !do_generate do return true  // If shader_gather points to a RenderPass then do nothing here

    dbg.log(.INFO, "Populating shaders for render pass")

    for &mesh in meshes {

        shader_pass, generate_ok := generate_shader_pass_for_mesh(shader_store, manager, shader_generate_type, mesh, allocator)
        if !generate_ok {
            dbg.log(.ERROR, "Could not populate shaders for mesh")
            return
        }

        if shader_pass == nil do continue

        mesh_id := shader_store.last_mesh_id
        dbg.log(.INFO, "New mesh id: %d", mesh_id)
        mesh.mesh_id = mesh_id
        shader_store.last_mesh_id += 1

        if render_pass not_in shader_store.render_pass_mappings {
            new_mapping := make(RenderShaderMapping, shader_store.render_pass_mappings.allocator)
            new_mapping[mesh_id] = shader_pass.?
            shader_store.render_pass_mappings[render_pass] = new_mapping
        }
        else {
            shader_mapping := &shader_store.render_pass_mappings[render_pass]
            shader_mapping[mesh_id] = shader_pass.?
        }
    }

    return true
}

@(private)
generate_shader_pass_for_mesh :: proc(
    shader_store: ^RenderShaderStore,
    manager: ^resource.ResourceManager,
    shader_generate: RenderPassShaderGenerate,
    mesh: ^resource.Mesh,
    allocator := context.allocator
) -> (shader_pass_id: resource.ResourceID, ok: bool) {
    // Upon .NO_GENERATE the pass gets ignored
    if mesh.mesh_id != nil || shader_generate == .NO_GENERATE {
        dbg.log(.INFO, "Skipping shader generation for mesh")
        return nil, true
    }

    dbg.log(.INFO, "Generating shader pass for mesh")

    vertex_layout := resource.get_vertex_layout(manager, mesh.layout) or_return
    material_type := resource.get_material(manager, mesh.material.type) or_return
    log.infof("layout: %v, mat: %v", mesh.layout, mesh.material.type)

    contains_tangent := false
    for info in vertex_layout.infos {
        if info.type == .tangent  {
            contains_tangent = true
            break
        }
    }

    if vertex_layout.shader == nil {
        dbg.log(dbg.LogLevel.INFO, "Creating vertex shader for layout")
        vertex_layout.shader = generate_vertex_shader(manager, shader_generate, contains_tangent, allocator) or_return
    }

    if material_type.shader == nil {
        dbg.log(dbg.LogLevel.INFO, "Creating lighting shader for material type")
        material_type.shader = generate_lighting_shader(manager, shader_generate, contains_tangent, allocator) or_return
    }

    // Grabbing shaders here makes it impossible to compile a shader twice
    vert := resource.get_shader(manager, vertex_layout.shader.?) or_return
    frag := resource.get_shader(manager, material_type.shader.?) or_return

    if vert.id == nil do compile_shader(vert) or_return
    if frag.id == nil do compile_shader(frag) or_return

    shader_pass := resource.init_shader_program()
    shader_pass.shaders[.VERTEX] = vertex_layout.shader.?
    shader_pass.shaders[.FRAGMENT] = material_type.shader.?

    shader_pass_id = resource.add_shader_pass(manager, shader_pass) or_return
    e_shader_pass := resource.get_shader_pass(manager, shader_pass_id) or_return
    transfer_shader_program(manager, e_shader_pass) or_return // Links, will attempt to compile but it doesn't matter

    return shader_pass_id, true
}

@(private)
generate_vertex_shader :: proc(
    manager: ^resource.ResourceManager,
    pass_type: RenderPassShaderGenerate,
    contains_tangent: bool,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    // Todo dynamic
    dbg.log(.INFO, "Generating vertex shader")

    single_shader: resource.Shader
    if contains_tangent do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr.vert", .VERTEX, allocator) or_return
    else do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr_no_tangent.vert", .VERTEX, allocator) or_return

    id = resource.add_shader(manager, single_shader) or_return
    ok = true
    return
}

@(private)
generate_lighting_shader :: proc(
    manager: ^resource.ResourceManager,
    pass_type: RenderPassShaderGenerate,
    contains_tangent: bool,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    // Todo dynamic
    dbg.log(.INFO, "Generating lighting shader")

    single_shader: resource.Shader
    if contains_tangent do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr.frag", .FRAGMENT, allocator) or_return
    else do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr_no_tangent.frag", .FRAGMENT, allocator) or_return
    id = resource.add_shader(manager, single_shader) or_return
    ok = true
    return
}


// Handles the pre render passes
pre_render :: proc(manager: ^resource.ResourceManager, pipeline: RenderPipeline, scene: ^ecs.Scene, temp_allocator := context.temp_allocator) -> (ok: bool) {

    for pass in pipeline.pre_passes {
        if len(pass.frame_buffers) == 0 {
            dbg.log(.ERROR, "Pre render pass must have more than one framebuffer")
            return
        }

        switch input in pass.input {
        case IBLInput:

            buffer := utils.safe_index(pipeline.frame_buffers, pass.frame_buffers[0]) or_return
            ok = ibl_pre_render_pass(manager, scene, buffer^)
            if !ok {
                dbg.log(.ERROR, "Failed to pre render IBL maps")
                return
            }
        }
    }

    ok = true
    return
}


ibl_pre_render_pass :: proc(
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    buffer: FrameBuffer,
    allocator := context.allocator,
    loc := #caller_location
) -> (ok: bool) {
    dbg.log(.INFO, "IBL Pre render pass")

    environment_m := &scene.image_environment
    if environment_m^ == nil {
        dbg.log(.ERROR, "No environment found in scene for IBL")
        return
    }
    environment: ^ecs.ImageEnvironment = &environment_m.?

    set_depth_test(true)
    gl.DepthFunc(gl.LEQUAL)
    gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

    transfer_texture(&environment.environment_tex, gl.RGB16F, 0, gl.RGBA, gl.FLOAT, true) or_return

    cube_comp := create_primitive_cube()
    defer release_gl_component(cube_comp)
    cube_vao := cube_comp.vao.?

    fbo := utils.unwrap_maybe(buffer.id) or_return

    depth_rbo := make_renderbuffer(IBL_FRAMEBUFFER_WIDTH, IBL_FRAMEBUFFER_HEIGHT, gl.DEPTH_COMPONENT24)
    rbo := utils.unwrap_maybe(depth_rbo.id) or_return

    bind_renderbuffer_to_frame_buffer(fbo, depth_rbo, .DEPTH)
    check_framebuffer_status(buffer, loc=loc) or_return
    dbg.log(.INFO, "Bound renderbuffer to frame buffer")

    project := glm.mat4Perspective(glm.radians_f32(90), 1, 0.1, 10)

    views := [6]matrix[4, 4]f32 {
        glm.mat4LookAt({0, 0, 0}, {1, 0, 0}, {0, -1, 0}),
        glm.mat4LookAt({0, 0, 0}, {-1, 0, 0}, {0, -1, 0}),
        glm.mat4LookAt({0, 0, 0}, {0, 1, 0}, {0, 0, 1}),
        glm.mat4LookAt({0, 0, 0}, {0, -1, 0}, {0, 0, -1}),
        glm.mat4LookAt({0, 0, 0}, {0, 0, 1}, {0, -1, 0}),
        glm.mat4LookAt({0, 0, 0}, {0, 0, -1}, {0, -1, 0}),
    }

    if environment.environment_map == nil do environment.environment_map = create_environment_map(manager, environment.environment_tex, project, views, fbo, cube_vao, allocator=allocator) or_return
    check_framebuffer_status(buffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl environment map")

    env_map := environment.environment_map.?
    env_cubemap := env_map.gpu_texture

    if environment.irradiance_map == nil do environment.irradiance_map = create_ibl_irradiance_map(
        manager,
        env_cubemap,
        project,
        views,
        fbo,
        rbo,
        cube_vao,
        allocator
    ) or_return
    check_framebuffer_status(buffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl irradiance map")


    if environment.prefilter_map == nil do environment.prefilter_map = create_ibl_prefilter_map(
        manager,
        env_cubemap,
        project,
        views,
        fbo,
        rbo,
        cube_vao,
        allocator
    ) or_return
    check_framebuffer_status(buffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl prefilter map")

    if environment.brdf_lookup == nil do environment.brdf_lookup = create_ibl_brdf_lookup(
        manager,
        fbo,
        rbo,
        allocator
    ) or_return
    check_framebuffer_status(buffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl brdf lookup table")

    bind_default_framebuffer()

    ok = true
    return
}

ENV_MAP_FACE_WIDTH :: 2048
ENV_MAP_FACE_HEIGHT :: 2048
create_environment_map :: proc(
    manager: ^resource.ResourceManager,
    environment_tex: resource.Texture,
    project: matrix[4, 4]f32,
    views: [6]matrix[4, 4]f32,
    fbo: u32,
    cube_vao: u32,
    w: i32 = ENV_MAP_FACE_WIDTH,
    h: i32 = ENV_MAP_FACE_HEIGHT,
    allocator := context.allocator
) -> (env: resource.Texture, ok: bool) {
    using env
    name = strings.clone("EnvironmentMap", allocator=allocator)

    properties = resource.default_texture_properties()
    properties[.MIN_FILTER] = .LINEAR_MIPMAP_LINEAR

    gpu_texture = make_texture(w, h, nil, gl.RGB16F, 0, gl.RGB, gl.FLOAT, resource.TextureType.CUBEMAP, properties, false)
    type = .CUBEMAP

    shader := get_environment_map_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    resource.set_uniform(&shader, "environmentTex", i32(0))
    resource.set_uniform(&shader, "m_Project", project)
    bind_texture(0, environment_tex.gpu_texture) or_return

    set_render_viewport(0, 0, w, h)

    bind_framebuffer_raw(fbo)
    for i in 0..<6 {
        resource.set_uniform(&shader, "m_View", views[i])
        bind_texture_to_frame_buffer(fbo, env, .COLOUR, u32(i), 0, 0) or_return
        clear_mask({ .COLOUR_BIT, .DEPTH_BIT })

        render_primitive_cube(cube_vao)
    }

    bind_default_framebuffer()

    bind_texture_raw(.CUBEMAP, gpu_texture.?)
    gen_mipmap(.CUBEMAP)

    ok = true
    return
}

@(private)
get_environment_map_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (shader: resource.ShaderProgram, ok: bool) {
    vert := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "cubemap.vert", .VERTEX) or_return
    frag := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "equirectangular_to_cubemap.frag", .FRAGMENT) or_return
    shader = resource.make_shader_program(manager, []resource.Shader{ vert, frag }, allocator) or_return
    transfer_shader_program(manager, &shader) or_return

    attach_program(shader) or_return

    ok = true
    return
}

IRRADIANCE_MAP_FACE_WIDTH :: 32
IRRADIANCE_MAP_FACE_HEIGHT :: 32
create_ibl_irradiance_map :: proc(
    manager: ^resource.ResourceManager,
    env_cubemap: GPUTexture,
    project: matrix[4, 4]f32,
    views: [6]matrix[4, 4]f32,
    fbo: u32,
    rbo: u32,
    cube_vao: u32,
    allocator := context.allocator
) -> (irradiance: resource.Texture, ok: bool) {
    using irradiance
    name = strings.clone("IrradianceMap", allocator=allocator)

    properties = resource.default_texture_properties()
    gpu_texture = make_texture(IRRADIANCE_MAP_FACE_WIDTH, IRRADIANCE_MAP_FACE_WIDTH, nil, gl.RGB16F, 0, gl.RGB, gl.FLOAT, resource.TextureType.CUBEMAP, properties, false)
    type = .CUBEMAP

    bind_framebuffer_raw(fbo)
    bind_renderbuffer_raw(rbo)
    set_render_buffer_storage(gl.DEPTH_COMPONENT24, IRRADIANCE_MAP_FACE_WIDTH, IRRADIANCE_MAP_FACE_HEIGHT)

    shader := get_ibl_irradiance_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    resource.set_uniform(&shader, "environmentMap", i32(0))
    resource.set_uniform(&shader, "m_Project", project)
    bind_texture(0, env_cubemap, .CUBEMAP) or_return

    set_render_viewport(0, 0, IRRADIANCE_MAP_FACE_WIDTH, IRRADIANCE_MAP_FACE_HEIGHT)
    bind_framebuffer_raw(fbo)
    for i in 0..<6 {
        resource.set_uniform(&shader, "m_View", views[i])
        bind_texture_to_frame_buffer(fbo, irradiance, .COLOUR, u32(i), 0, 0)
        clear_mask({ .COLOUR_BIT, .DEPTH_BIT })

        render_primitive_cube(cube_vao)
    }

    ok = true
    return
}

@(private)
get_ibl_irradiance_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (shader: resource.ShaderProgram, ok: bool) {
    vert := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "cubemap.vert", .VERTEX) or_return
    frag := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "ibl_irradiance.frag", .FRAGMENT) or_return
    shader = resource.make_shader_program(manager, []resource.Shader{ vert, frag }, allocator) or_return
    transfer_shader_program(manager, &shader) or_return

    attach_program(shader) or_return

    ok = true
    return
}

PREFILTER_MAP_FACE_WIDTH :: 1024
PREFILTER_MAP_FACE_HEIGHT :: 1024
create_ibl_prefilter_map :: proc(
    manager: ^resource.ResourceManager,
    env_cubemap: GPUTexture,
    project: matrix[4, 4]f32,
    views: [6]matrix[4, 4]f32,
    fbo: u32,
    rbo: u32,
    cube_vao: u32,
    allocator := context.allocator
) -> (prefilter: resource.Texture, ok: bool) {
    using prefilter
    name = strings.clone("PrefilterMap", allocator=allocator)

    properties = resource.default_texture_properties()
    properties[.MIN_FILTER] = .LINEAR_MIPMAP_LINEAR
    gpu_texture = make_texture(PREFILTER_MAP_FACE_WIDTH, PREFILTER_MAP_FACE_HEIGHT, nil, gl.RGB16F, 0, gl.RGB, gl.FLOAT, resource.TextureType.CUBEMAP, properties, true)
    type = .CUBEMAP

    shader := get_ibl_prefilter_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    resource.set_uniform(&shader, "environmentMap", i32(0))
    resource.set_uniform(&shader, "m_Project", project)
    bind_texture(0, env_cubemap, .CUBEMAP) or_return

    bind_framebuffer_raw(fbo)
    MIP_LEVELS :: 5
    for mip in 0..<MIP_LEVELS {

        mip_width := i32(PREFILTER_MAP_FACE_WIDTH * math.pow(0.5, f32(mip)))
        mip_height := i32(PREFILTER_MAP_FACE_HEIGHT * math.pow(0.5, f32(mip)))

        bind_renderbuffer_raw(rbo)
        set_render_buffer_storage(gl.DEPTH_COMPONENT24, mip_width, mip_height)
        check_framebuffer_status_raw() or_return

        set_render_viewport(0, 0, mip_width, mip_height)

        roughness: f32 = f32(mip) / f32(MIP_LEVELS - 1)
        resource.set_uniform(&shader, "roughness", roughness)

        for i in 0..<6 {
            resource.set_uniform(&shader, "m_View", views[i])
            bind_texture_to_frame_buffer(fbo, prefilter, .COLOUR, u32(i), 0, i32(mip))
            check_framebuffer_status_raw() or_return

            clear_mask({ .COLOUR_BIT, .DEPTH_BIT })

            render_primitive_cube(cube_vao)
        }

        check_framebuffer_status_raw() or_return
    }

    ok = true
    return
}

@(private)
get_ibl_prefilter_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (shader: resource.ShaderProgram, ok: bool) {
    vert := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "cubemap.vert", .VERTEX) or_return
    frag := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "ibl_prefilter.frag", .FRAGMENT) or_return
    shader = resource.make_shader_program(manager, []resource.Shader{ vert, frag }, allocator) or_return
    transfer_shader_program(manager, &shader) or_return

    attach_program(shader) or_return

    ok = true
    return
}

IBL_BRDF_LUT_WIDTH :: 512
IBL_BRDF_LUT_HEIGHT :: 512
create_ibl_brdf_lookup :: proc(
    manager: ^resource.ResourceManager,
    fbo: u32,
    rbo: u32,
    allocator := context.allocator
) -> (brdf_lut: resource.Texture, ok: bool) {
    using brdf_lut
    name = strings.clone("BrdfLUT", allocator=allocator)
    properties = resource.default_texture_properties(allocator)
    gpu_texture = make_texture(IBL_BRDF_LUT_WIDTH, IBL_BRDF_LUT_HEIGHT, nil, gl.RG16, 0, gl.RG, gl.FLOAT, resource.TextureType.TWO_DIM, properties, false)
    type = .TWO_DIM

    shader := get_ibl_brdf_lut_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    bind_framebuffer_raw(fbo)
    bind_renderbuffer_raw(rbo)
    set_render_buffer_storage(gl.DEPTH_COMPONENT24, IBL_BRDF_LUT_WIDTH, IBL_BRDF_LUT_HEIGHT)
    bind_texture_to_frame_buffer(fbo, brdf_lut, .COLOUR)

    set_render_viewport(0, 0, IBL_BRDF_LUT_WIDTH, IBL_BRDF_LUT_HEIGHT)
    clear_mask({ .COLOUR_BIT, .DEPTH_BIT })

    quad_comp := create_primitive_quad()
    defer release_gl_component(quad_comp)

    render_primitive_quad(quad_comp.vao.?)

    ok = true
    return
}

@(private)
get_ibl_brdf_lut_shader :: proc(manager: ^resource.ResourceManager, allocator := context.allocator) -> (shader: resource.ShaderProgram, ok: bool) {
    vert := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "ibl_brdf.vert", .VERTEX) or_return
    frag := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "ibl_brdf.frag", .FRAGMENT) or_return
    shader = resource.make_shader_program(manager, []resource.Shader{ vert, frag }, allocator) or_return
    transfer_shader_program(manager, &shader) or_return

    attach_program(shader) or_return

    ok = true
    return
}


IBL_FRAMEBUFFER_WIDTH :: ENV_MAP_FACE_WIDTH
IBL_FRAMEBUFFER_HEIGHT :: ENV_MAP_FACE_HEIGHT

make_ibl_framebuffer :: proc(allocator := context.allocator) -> (buffer: FrameBuffer) {
    return make_framebuffer(IBL_FRAMEBUFFER_WIDTH, IBL_FRAMEBUFFER_HEIGHT, allocator=allocator)
}

// Just using learnopengl here, obviously using indexed would be better, but marginally so
create_primitive_cube :: proc() -> (comp: resource.GLComponent) {
    verts := [36 * 8]f32 {
        -1.0, -1.0, -1.0,  0.0,  0.0, -1.0, 0.0, 0.0,
        1.0,  1.0, -1.0,  0.0,  0.0, -1.0, 1.0, 1.0,
        1.0, -1.0, -1.0,  0.0,  0.0, -1.0, 1.0, 0.0,
        1.0,  1.0, -1.0,  0.0,  0.0, -1.0, 1.0, 1.0,
        -1.0, -1.0, -1.0,  0.0,  0.0, -1.0, 0.0, 0.0,
        -1.0,  1.0, -1.0,  0.0,  0.0, -1.0, 0.0, 1.0,
        -1.0, -1.0,  1.0,  0.0,  0.0,  1.0, 0.0, 0.0,
        1.0, -1.0,  1.0,  0.0,  0.0,  1.0, 1.0, 0.0,
        1.0,  1.0,  1.0,  0.0,  0.0,  1.0, 1.0, 1.0,
        1.0,  1.0,  1.0,  0.0,  0.0,  1.0, 1.0, 1.0,
        -1.0,  1.0,  1.0,  0.0,  0.0,  1.0, 0.0, 1.0,
        -1.0, -1.0,  1.0,  0.0,  0.0,  1.0, 0.0, 0.0,
        -1.0,  1.0,  1.0, -1.0,  0.0,  0.0, 1.0, 0.0,
        -1.0,  1.0, -1.0, -1.0,  0.0,  0.0, 1.0, 1.0,
        -1.0, -1.0, -1.0, -1.0,  0.0,  0.0, 0.0, 1.0,
        -1.0, -1.0, -1.0, -1.0,  0.0,  0.0, 0.0, 1.0,
        -1.0, -1.0,  1.0, -1.0,  0.0,  0.0, 0.0, 0.0,
        -1.0,  1.0,  1.0, -1.0,  0.0,  0.0, 1.0, 0.0,
        1.0,  1.0,  1.0,  1.0,  0.0,  0.0, 1.0, 0.0,
        1.0, -1.0, -1.0,  1.0,  0.0,  0.0, 0.0, 1.0,
        1.0,  1.0, -1.0,  1.0,  0.0,  0.0, 1.0, 1.0,
        1.0, -1.0, -1.0,  1.0,  0.0,  0.0, 0.0, 1.0,
        1.0,  1.0,  1.0,  1.0,  0.0,  0.0, 1.0, 0.0,
        1.0, -1.0,  1.0,  1.0,  0.0,  0.0, 0.0, 0.0,
        -1.0, -1.0, -1.0,  0.0, -1.0,  0.0, 0.0, 1.0,
        1.0, -1.0, -1.0,  0.0, -1.0,  0.0, 1.0, 1.0,
        1.0, -1.0,  1.0,  0.0, -1.0,  0.0, 1.0, 0.0,
        1.0, -1.0,  1.0,  0.0, -1.0,  0.0, 1.0, 0.0,
        -1.0, -1.0,  1.0,  0.0, -1.0,  0.0, 0.0, 0.0,
        -1.0, -1.0, -1.0,  0.0, -1.0,  0.0, 0.0, 1.0,
        -1.0,  1.0, -1.0,  0.0,  1.0,  0.0, 0.0, 1.0,
        1.0,  1.0 , 1.0,  0.0,  1.0,  0.0, 1.0, 0.0,
        1.0,  1.0, -1.0,  0.0,  1.0,  0.0, 1.0, 1.0,
        1.0,  1.0,  1.0,  0.0,  1.0,  0.0, 1.0, 0.0,
        -1.0,  1.0, -1.0,  0.0,  1.0,  0.0, 0.0, 1.0,
        -1.0,  1.0,  1.0,  0.0,  1.0,  0.0, 0.0, 0.0
    }

    create_and_transfer_vao(&comp.vao)
    verts_dyn := transmute([dynamic]f32)runtime.Raw_Dynamic_Array{ &verts[0], len(verts), len(verts), context.allocator }
    layout := []resource.MeshAttributeInfo{
        resource.MeshAttributeInfo{ .position, .vec3, .f32, 12, 3, "" },
        resource.MeshAttributeInfo{ .normal, .vec2, .f32, 12, 3, "" },
        resource.MeshAttributeInfo{ .texcoord, .vec2, .f32, 8, 2, "" },
    }
    create_and_transfer_vbo_maybe(&comp.vbo, verts_dyn, layout)

    return
}

render_primitive_cube :: proc(vao: u32) {
    dbg.log()
    gl.BindVertexArray(vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 36)
    gl.BindVertexArray(0)
}

render_primitive_quad :: proc(vao: u32) {
    dbg.log()
    gl.BindVertexArray(vao)
    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)
    gl.BindVertexArray(0)
}


create_primitive_quad :: proc() -> (comp: resource.GLComponent) {
    verts := [5 * 4]f32 {
        -1,  1, 0,  0, 1,
         1,  1, 0,  1, 1,
        -1, -1, 0,  0, 0,
         1, -1, 0,  1, 0,
    }

    vao: u32
    gl.GenVertexArrays(1, &vao)
    gl.BindVertexArray(vao)
    comp.vao = vao

    vbo: u32
    gl.GenBuffers(1, &vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(verts), raw_data(&verts), gl.STATIC_DRAW)
    comp.vbo = vbo

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 20, 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 20, 12)

    return
}
