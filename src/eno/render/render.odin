package render

import gl "vendor:OpenGL"
import rdoc "../../../libs/odin-renderdoc"

import "../ecs"
import "../resource"
import "../utils"
import dbg "../debug"
import "../standards"
import lutils "../utils/linalg_utils"
import cam "../camera"
import "../ui"
import "../window"

import "core:math/linalg"
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
    skybox_shader: ^resource.ShaderProgram,
    image_environment: Maybe(ImageEnvironment),
    pipeline: RenderPipeline,
    manager: ^resource.ResourceManager,
    renderdoc: Maybe(RenderDoc),
    primitives: RenderPrimitives,
    allocator: mem.Allocator
}

RenderPrimitives :: struct {
    cube: ^resource.Mesh,
    quad: ^resource.Mesh,
    triangle: ^resource.Mesh
}

create_render_primitives :: proc(allocator := context.allocator) -> (ok: bool) {
    if Context.manager == nil {
        dbg.log(.ERROR, "Manager must not be nil")
        return
    }

    if Context.primitives.cube == nil {
        mesh := create_primitive_cube_mesh(Context.manager) or_return
        Context.primitives.cube = new(resource.Mesh, allocator)
        Context.primitives.cube^ = mesh
    }
    if Context.primitives.quad == nil {
        mesh := create_primitive_quad_mesh(Context.manager) or_return
        Context.primitives.cube = new(resource.Mesh, allocator)
        Context.primitives.cube^ = mesh
    }
    // if Context.primitives.triangle == nil do /* todo */ ;

    return true
}


Context: RenderContext

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
    scene: ^ecs.Scene,
    allocator := context.allocator,
    temp_allocator := context.temp_allocator
) -> (ok: bool) {
    pipeline := Context.pipeline
    Context.manager = manager
    Context.allocator = allocator

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
        mesh_data := meshes_from_gather(manager, scene, &mesh_data_map, &mesh_data_references, pass, temp_allocator) or_return

        // Handle properties BEFORE 0 mesh check
        handle_pass_state(pass^) or_return
        check_framebuffer_status_raw() or_return

        update_camera_ubo(scene) or_return
        update_lights_ssbo(scene) or_return

        if len(mesh_data) != 0 do render_geometry(manager, scene, pipeline.shader_store, pass, mesh_data, temp_allocator) or_return
        if pass.properties.render_skybox do render_skybox(manager, scene.viewpoint, allocator) or_return
    }


    ui.render_ui(window.WINDOW_WIDTH, window.WINDOW_HEIGHT) or_return

    return true
}

@(private)
meshes_from_gather :: proc(
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    mesh_data_map: ^map[^RenderPass][dynamic]MeshData,
    mesh_data_references: ^map[^RenderPass]^[dynamic]MeshData,
    pass: ^RenderPass,
    temp_allocator: mem.Allocator
) -> (res: []MeshData, ok: bool) {

    mesh_data: ^[dynamic]MeshData
    switch &mesh_gather_variant in pass.mesh_gather {
        case ^RenderPass:
            if mesh_gather_variant not_in mesh_data_map {
                if mesh_gather_variant not_in mesh_data_references {
                    dbg.log(.ERROR, "Render pass gather points to a render pass which has not yet been assigned model data, order the render-passes to fix")
                    return
                }

                mesh_data = mesh_data_references[mesh_gather_variant]
            }
            else do mesh_data = &mesh_data_map[mesh_gather_variant]
            mesh_data_references[pass] = mesh_data
        case SinglePrimitiveMesh:
            mesh: ^resource.Mesh
            switch mesh_gather_variant.type {
                case .CUBE:
                    if Context.primitives.cube == nil {
                        dbg.log(.ERROR, "Cube primitive must be available")
                        return
                    }
                    mesh = Context.primitives.cube
                case .QUAD:
                    if Context.primitives.quad == nil {
                        dbg.log(.ERROR, "Quad primitive must be available")
                        return
                    }
                    mesh = Context.primitives.quad
                case .TRIANGLE:
                    if Context.primitives.triangle == nil {
                        dbg.log(.ERROR, "Triangle primitive must be available")
                        return
                    }
                    mesh = Context.primitives.triangle
            }
            mesh_data := MeshData{ mesh, &mesh_gather_variant.world, nil }
        case RenderPassQuery:
            mesh_data_map[pass] = query_scene(manager, scene, mesh_gather_variant, temp_allocator) or_return
            mesh_data = &mesh_data_map[pass]
        case nil:
            mesh_data_map[pass] = query_scene(manager, scene, {}, temp_allocator) or_return
            mesh_data = &mesh_data_map[pass]
    }
    if mesh_data == nil {
        dbg.log(.ERROR, "Mesh data returned nil")
        return
    }

    return mesh_data[:], true
}

@(private)
render_geometry :: proc(
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    shader_store: RenderShaderStore,
    pass: ^RenderPass,
    mesh_data: []MeshData,
    temp_allocator := context.temp_allocator
) -> (ok: bool) {
    sort_geom := pass.properties.geometry_z_sorting != .NO_SORT
    if sort_geom do sort_geometry_by_depth(scene.viewpoint.position, mesh_data[:], pass.properties.geometry_z_sorting == .ASC)

    // Group geometry by shaders
    shader_map := group_meshes_by_shader(shader_store, pass, mesh_data, sort_geom, temp_allocator) or_return

    // render meshes
    for mapping in shader_map {
        shader_pass := resource.get_shader_pass(manager, mapping.shader) or_return
        attach_program(shader_pass^)

        lighting_settings := get_lighting_settings()
        resource.set_uniform(shader_pass, LIGHTING_SETTINGS, transmute(u32)(lighting_settings))
        if .IBL in lighting_settings do bind_ibl_uniforms(shader_pass)

        for mesh_data in mapping.meshes {
            model_mat, normal_mat := model_and_normal(mesh_data.mesh, mesh_data.world, scene.viewpoint)
            transfer_mesh(manager, mesh_data.mesh) or_return

            material_type := resource.get_material(manager, mesh_data.mesh.material.type) or_return
            bind_material_uniforms(manager, mesh_data.mesh.material, material_type^, shader_pass) or_return

            if pass.properties.face_culling == FaceCulling.ADAPTIVE {
                if material_type.double_sided do set_face_culling(false)
                else do cull_geometry_faces(.BACK)
            }

            resource.set_uniform(shader_pass, standards.MODEL_MAT, model_mat)
            resource.set_uniform(shader_pass, standards.NORMAL_MAT, normal_mat)

            issue_draw_call_for_mesh(mesh_data.mesh)
        }
    }

    return true
}

// Allocator is perm content, not temp
@(private)
render_skybox :: proc(manager: ^resource.ResourceManager, viewpoint: ^cam.Camera, allocator := context.allocator) -> (ok: bool) {
    if Context.image_environment == nil do return true

    env := Context.image_environment.?
    if env.environment_map == nil {
        dbg.log(.ERROR, "Image environment map must be avaiable to render skybox")
        return
    }

    env_map := env.environment_map.?
    if env_map.gpu_texture == nil {
        dbg.log(.ERROR, "Environment cubemap gpu texture is not provided")
        return
    }

    if Context.skybox_comp == nil {
        Context.skybox_comp = new(resource.GLComponent)
        Context.skybox_comp^ = create_primitive_cube()
    }

    if Context.skybox_comp.vao == nil {
        dbg.log(.ERROR, "Vertex array nil is unexpected in skybox render")
        return
    }

    if Context.skybox_shader == nil {
        Context.skybox_shader = new(resource.ShaderProgram)
        Context.skybox_shader^ = create_skybox_shader(manager, allocator) or_return
    }

    attach_program(Context.skybox_shader^) or_return

    view := glm.mat4(glm.mat3(viewpoint.look_at))
    resource.set_uniform(Context.skybox_shader, VIEW_MATRIX_UNIFORM, view)
    resource.set_uniform(Context.skybox_shader, PROJECTION_MATRIX_UNIFORM, viewpoint.perspective)

    bind_texture(0, env_map.gpu_texture.?, .CUBEMAP)
    resource.set_uniform(Context.skybox_shader, ENV_MAP_UNIFORM, i32(0))

    cull_geometry_faces(.FRONT) // We see the back faces of the cube
    set_depth_func(.LEQUAL)
    render_primitive_cube(Context.skybox_comp.vao.?)

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


BRDF_LUT_UNIFORM :: "brdfLut"
PREFILTER_MAP_UNIFORM :: "prefilterMap"
IRRADIANCE_MAP_UNIFORM :: "irradianceMap"
@(private)
bind_ibl_uniforms :: proc( shader: ^resource.ShaderProgram) -> (ok: bool) {
    m_env := Context.image_environment
    if m_env == nil {
        dbg.log(.ERROR, "Scene image environment for ibl not yet setup")
        return
    }

    env := m_env.?
    if env.environment_map == nil || env.brdf_lookup == nil || env.irradiance_map == nil || env.prefilter_map == nil {
        dbg.log(.ERROR, "Not all IBL textures/cubemaps are available, environment: %#v", env)
        return
    }
    irradiance_map := env.irradiance_map.?
    prefilter_map := env.prefilter_map.?
    brdf_lut := env.brdf_lookup.?

    texture_unit: i32
    texture_unit = i32(PBRSamplerBindingLocation.IRRADIANCE_MAP)
    bind_texture(texture_unit, irradiance_map.gpu_texture, irradiance_map.type) or_return
    resource.set_uniform(shader, IRRADIANCE_MAP_UNIFORM, texture_unit)

    texture_unit = i32(PBRSamplerBindingLocation.BRDF_LUT)
    bind_texture(texture_unit, brdf_lut.gpu_texture, brdf_lut.type) or_return
    resource.set_uniform(shader, BRDF_LUT_UNIFORM, texture_unit)

    texture_unit = i32(PBRSamplerBindingLocation.PREFILTER_MAP)
    bind_texture(texture_unit, prefilter_map.gpu_texture, prefilter_map.type) or_return
    resource.set_uniform(shader, PREFILTER_MAP_UNIFORM, texture_unit)

    ok = true
    return
}

ShaderMeshRenderMapping :: struct {
    shader: resource.ResourceIdent,
    meshes: [dynamic]MeshData
}

@(private)
group_meshes_by_shader :: proc(
    shader_store: RenderShaderStore,
    render_pass: ^RenderPass,
    meshes: []MeshData,
    preserve_ordering: bool,
    temp_allocator := context.temp_allocator
) -> (result: []ShaderMeshRenderMapping, ok: bool) {
    if len(meshes) == 0 {
        dbg.log(.ERROR, "Cannot group 0 meshes")
        return
    }

    // Get shader mapping from RenderShaderStore
    render_shader_mapping, mapping_exists := shader_store.render_pass_mappings[render_pass]
    if !mapping_exists {
        dbg.log(.ERROR, "No shader mapping exists for render pass")
        return
    }

    shader_mappings := make([dynamic]ShaderMeshRenderMapping, allocator=temp_allocator)

    if !preserve_ordering {
        // Maps shader id to index in shader_mappings
        mapping_reference := make(map[resource.ResourceIdent]int, allocator=temp_allocator)

        for &mesh_data in meshes {
            mesh := mesh_data.mesh
            if mesh.mesh_id == nil || mesh.mesh_id.? not_in render_shader_mapping {
                dbg.log(.ERROR, "Shader pass not generated for mesh: %#v", mesh.material)
                return
            }

            shader_id := render_shader_mapping[mesh.mesh_id.?]

            if shader_id in mapping_reference {
                dyn := &shader_mappings[mapping_reference[shader_id]].meshes
                append(dyn, mesh_data)
            }
            else {
                dyn := make([dynamic]MeshData, 1, allocator=temp_allocator)
                dyn[0] = mesh_data
                append(&shader_mappings, ShaderMeshRenderMapping{ shader_id, dyn })
                mapping_reference[shader_id] = len(shader_mappings) - 1
            }

        }
    }
    else {
        current_shader: resource.ResourceIdent
        for &mesh_data in meshes {
            mesh := mesh_data.mesh
            if mesh.mesh_id == nil || mesh.mesh_id.? not_in render_shader_mapping {
                dbg.log(.ERROR, "Shader pass not generated for mesh: %#v", mesh.material)
                return
            }

            shader_id := render_shader_mapping[mesh.mesh_id.?]
            if shader_id == current_shader {
                if len(shader_mappings) == 0 {
                    dbg.log(.ERROR, "Error in shader mappings")
                    return
                }

                append(&shader_mappings[len(shader_mappings) - 1].meshes, mesh_data)
            }
            else {
                dyn := make([dynamic]MeshData, 1, allocator=temp_allocator)
                dyn[0] = mesh_data
                append(&shader_mappings, ShaderMeshRenderMapping{ shader_id, dyn })
                current_shader = shader_id
            }
        }

    }

    return shader_mappings[:], true
}


// Handles binding of framebuffer along with enabling of certain settings/tests
@(private)
handle_pass_state :: proc(pass: RenderPass) -> (ok: bool) {
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
        bind_framebuffer(pass.frame_buffer^) or_return
        if pass.properties.viewport != nil {
            viewport := pass.properties.viewport.?
            set_render_viewport(viewport[0], viewport[1], viewport[2], viewport[3])
        }
        else do set_render_viewport(0, 0, pass.frame_buffer.w, pass.frame_buffer.h)
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

    if properties.depth_func != nil do set_depth_func(properties.depth_func.?)
    else do set_default_depth_func()

    if properties.face_culling != nil {
        cull_geometry_faces(properties.face_culling.?)
    }
    else do set_face_culling(false)

    if properties.polygon_mode != nil {
        set_polygon_mode(properties.polygon_mode.?)
    }
    else do set_default_polygon_mode()

    set_multisampling(properties.multisample)

    if properties.clear_colour != nil {
        set_clear_colour(properties.clear_colour.?)
    } else do set_clear_colour()

    clear_mask(properties.clear)

    return true
}


@(private)
sort_geometry_by_depth :: proc(camera_pos: [3]f32, meshes_data: []MeshData, depth_asc: bool) {
    distances := make([]f32, len(meshes_data))
    for i in 0..<len(meshes_data) {
        mesh_data := meshes_data[i]
        centroid_adj := mesh_data.world.position + mesh_data.world.scale * mesh_data.mesh.centroid;
        distances[i] = linalg.length(camera_pos - centroid_adj)
    }

    sort_proc := depth_asc ? proc(a: f32, b: f32) -> bool {
        return a < b
    } : proc(a: f32, b: f32) -> bool {
        return a > b
    }

    indices := slice.sort_by_with_indices(distances, sort_proc); defer delete(indices)
    utils.rearrange_via_indices(meshes_data, indices)
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

/*
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
*/

model_and_normal :: proc(mesh: ^resource.Mesh, world: ^standards.WorldComponent, cam: ^cam.Camera) -> (model: glm.mat4, normal: glm.mat3) {
    // world_comp := mesh.is_billboard ? apply_billboard_rotation(cam.position, world^) : world^
    world_comp := world^
    model = standards.model_from_world_component(world_comp, mesh.transpose_transformation)
    normal = lutils.normal_mat(model)
    return
}

// Cannot use material infos from Material struct because some textures are
//  not available even if the specific mat property is used
// I've made this pascal case for some reason
MAX_MATERIAL_USAGE :: u32  // Must be reflected as the same type in any shaders
MaterialUsage :: enum {
    BaseColourFactor = 0,
    BaseColourTexture = 1,
    PBRMetallicFactor = 2,
    PBRRoughnessFactor = 3,
    PBRMetallicRoughnessTexture = 4,
    EmissiveFactor = 5,
    EmissiveTexture = 6,
    OcclusionTexture = 7,
    NormalTexture = 8,
    ClearcoatFactor = 9,
    ClearcoatTexture = 10,
    ClearcoatRoughnessFactor = 11,
    ClearcoatRoughnessTexture = 12,
    ClearcoatNormalTexture = 13,
    SpecularFactor = 14,
    SpecularTexture = 15,
    SpecularColourFactor = 16,
    SpecularColourTexture = 17
}
MaterialUsages :: bit_set[MaterialUsage; MAX_MATERIAL_USAGE]

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
    PREFILTER_MAP,
    SPECULAR,
    SPECULAR_COLOUR
}

@(private)
bind_material_uniforms :: proc(manager: ^resource.ResourceManager, material: resource.Material, type: resource.MaterialType, lighting_shader: ^resource.ShaderProgram) -> (ok: bool) {
    resource.set_uniform(lighting_shader, resource.ALPHA_CUTOFF, material.alpha_cutoff)
    resource.set_uniform(lighting_shader, resource.ENABLE_ALPHA_CUTOFF, i32(type.alpha_mode == .MASK))
    resource.set_uniform(lighting_shader, resource.UNLIT, i32(type.unlit))
    resource.set_uniform(lighting_shader, resource.EMISSIVE_FACTOR, material.emissive_factor[0], material.emissive_factor[1], material.emissive_factor[2])

    usages: MaterialUsages
    usages += { .EmissiveFactor }
    for info, property in material.properties {
        switch v in property.value {
            case resource.PBRMetallicRoughness:
                usages += { .BaseColourFactor, .PBRMetallicFactor, .PBRRoughnessFactor }
                if v.base_colour != nil {
                    usages += { .BaseColourTexture }
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
                resource.set_uniform(lighting_shader, resource.ENABLE_BASE_COLOUR_OVERRIDE, i32(v.enable_base_colour_override))

                if v.enable_base_colour_override {
                    resource.set_uniform(lighting_shader, resource.BASE_COLOUR_OVERRIDE, v.base_colour_override[0], v.base_colour_override[1], v.base_colour_override[2])
                }

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
                usages += { .ClearcoatFactor, .ClearcoatRoughnessFactor }
                if v.clearcoat_texture != nil {
                    usages += { .ClearcoatTexture }
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
            case resource.Specular:
                usages += { .SpecularFactor, .SpecularColourFactor }
                if v.specular_texture != nil {
                    usages += { .SpecularTexture }
                    specular := resource.get_texture(manager, v.specular_texture) or_return
                    texture_unit := i32(PBRSamplerBindingLocation.SPECULAR)

                    transfer_texture(specular)
                    bind_texture(texture_unit, specular.gpu_texture) or_return
                    resource.set_uniform(lighting_shader, resource.SPECULAR_TEXTURE, texture_unit)
                }

                if v.specular_colour_texture != nil {
                    usages += { .SpecularColourTexture }
                    specular_colour := resource.get_texture(manager, v.specular_colour_texture) or_return
                    texture_unit := i32(PBRSamplerBindingLocation.SPECULAR_COLOUR)

                    transfer_texture(specular_colour)
                    bind_texture(texture_unit, specular_colour.gpu_texture) or_return
                    resource.set_uniform(lighting_shader, resource.SPECULAR_COLOUR_TEXTURE, texture_unit)
                }

                resource.set_uniform(lighting_shader, resource.SPECULAR_FACTOR, v.specular_factor)
                resource.set_uniform(lighting_shader, resource.SPECULAR_COLOUR_FACTOR, v.specular_colour_factor[0], v.specular_colour_factor[1], v.specular_colour_factor[2])
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

    if Context.camera_ubo == nil {
        Context.camera_ubo = new(ShaderBuffer)
        Context.camera_ubo^ = make_shader_buffer(&camera_buffer_data, size_of(CameraBufferData), .UBO, 0, { .WRITE_MANY_READ_MANY, .DRAW })
    }
    else {
        ubo := Context.camera_ubo
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

    if Context.lights_ssbo == nil {
        Context.lights_ssbo = new(ShaderBuffer)
        Context.lights_ssbo^ = make_shader_buffer(raw_data(light_ssbo_data), len(light_ssbo_data), .SSBO, 1, { .WRITE_MANY_READ_MANY, .DRAW })
    }
    else {
        ssbo := Context.lights_ssbo
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


RenderPassMappings :: map[^RenderPass]RenderPassMapping
RenderPassMapping :: map[resource.MeshIdent]resource.ResourceIdent
RenderShaderStore :: struct {
    last_mesh_id: resource.MeshIdent,
    render_pass_mappings: RenderPassMappings
}

init_shader_store :: proc(allocator := context.allocator) -> (shader_store: RenderShaderStore) {
    shader_store.render_pass_mappings = make(RenderPassMappings, allocator)
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

populate_all_shaders :: proc(
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    allocator := context.allocator,
    temp_allocator := context.temp_allocator
) -> (ok: bool) {
    mesh_data_map := make(map[^RenderPass][dynamic]MeshData, allocator=temp_allocator)
    mesh_data_references := make(map[^RenderPass]^[dynamic]MeshData, allocator=temp_allocator)


    for pass in Context.pipeline.passes {
        meshes_data := meshes_from_gather(manager, scene, &mesh_data_map, &mesh_data_references, pass, temp_allocator) or_return
        populate_shaders(&Context.pipeline.shader_store, manager, scene, pass, meshes_data, allocator, temp_allocator) or_return
    }

    ok = true
    return
}

// Call when you have new meshes to populate shader_store and manager with
// todo see if unique field should be a mesh thing rather than a vertex layout/material type thing
// todo -  currently not doing anything with the field
populate_shaders :: proc(
    shader_store: ^RenderShaderStore,
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    render_pass: ^RenderPass,
    meshes_data: []MeshData,
    allocator := context.allocator,
    temp_allocator := context.temp_allocator
) -> (ok: bool) {
    dbg.log(.INFO, "Populating render pass '%s' for %d meshes", render_pass.name, len(meshes_data))

    shader_generator, generator_options := get_shader_generator(render_pass) or_return
    for &mesh_data in meshes_data {
        mesh := mesh_data.mesh
        if mesh.mesh_id == nil {
            mesh.mesh_id = shader_store.last_mesh_id
            shader_store.last_mesh_id += 1
        }

        // Get mapping
        if render_pass not_in shader_store.render_pass_mappings {
            new_mapping := make(RenderPassMapping, allocator=shader_store.render_pass_mappings.allocator)
            shader_store.render_pass_mappings[render_pass] = new_mapping
        }
        mapping: ^RenderPassMapping = &shader_store.render_pass_mappings[render_pass]

        shader_pass, generate_ok := generate_shader_pass_for_mesh(shader_store, manager, shader_generator, generator_options, mesh, allocator)
        if !generate_ok {
            dbg.log(.ERROR, "Could not populate shaders for mesh")
            return
        }

        if shader_pass == nil do continue

        mapping[mesh.mesh_id.(resource.MeshIdent)] = shader_pass.(resource.ResourceIdent)
    }

    return true
}


get_shader_generator :: proc(pass: ^RenderPass) -> (shader_generator: GenericShaderPassGenerator, generator_options: rawptr, ok: bool) {

    switch &shader_gather_variant in pass.shader_gather {
        case RenderPassShaderGenerate:
            shader_generator, generator_options = get_generator_from_config(&shader_gather_variant)
        case ^RenderPass: switch &reference_variant in shader_gather_variant.shader_gather {
            case RenderPassShaderGenerate:
                shader_generator, generator_options = get_generator_from_config(&reference_variant)
            case ^RenderPass:
                dbg.log(.ERROR, "Shader gather reference must not reference another shader gather")
                return
            case GenericShaderPassGenerator:
                shader_generator = reference_variant
            }
        case GenericShaderPassGenerator:
            shader_generator = shader_gather_variant
    }

    ok = true
    return
}

@(private)
get_generator_from_config :: proc(config: ^RenderPassShaderGenerate) -> (shader_generator: GenericShaderPassGenerator, generator_options: rawptr) {
    switch &generate_config in config {
    case GBufferShaderGenerateConfig:
        shader_generator = generate_gbuffer_shader_pass
        generator_options = &generate_config
    case LightingShaderGenerateConfig:
        shader_generator = generate_lighting_shader_pass
        generator_options = &generate_config
    }
    return
}

@(private)
generate_shader_pass_for_mesh :: proc(
    shader_store: ^RenderShaderStore,
    manager: ^resource.ResourceManager,
    shader_generator: GenericShaderPassGenerator,
    generator_options: rawptr,
    mesh: ^resource.Mesh,
    allocator := context.allocator
) -> (shader_pass_id: resource.ResourceID, ok: bool) {

    dbg.log(.INFO, "Generating shader pass for mesh")

    vertex_layout := resource.get_vertex_layout(manager, mesh.layout) or_return
    material_type := resource.get_material(manager, mesh.material.type) or_return
    log.infof("layout: %v, mat: %v", mesh.layout, mesh.material.type)

    shader_pass: resource.ShaderProgram = shader_generator(manager, vertex_layout, material_type, generator_options, allocator) or_return

    shader_pass_id = resource.add_shader_pass(manager, shader_pass) or_return
    e_shader_pass := resource.get_shader_pass(manager, shader_pass_id) or_return
    transfer_shader_program(manager, e_shader_pass) or_return // Links, will attempt to compile but it doesn't matter

    return shader_pass_id, true
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

    dbg.log(dbg.LogLevel.INFO, "Creating gbuffer vertex shader")
    vert_id := generate_gbuffer_vertex_shader(manager, vertex_layout, allocator) or_return

    dbg.log(dbg.LogLevel.INFO, "Creating gbuffer fragment shader")
    config := cast(^GBufferShaderGenerateConfig)options
    frag_id := generate_gbuffer_frag_shader(manager, config^, vertex_layout, allocator) or_return

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

    shader_pass = resource.init_shader_program()
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
    // Todo dynamic
    dbg.log(.INFO, "Generating lighting vertex shader")

    single_shader: resource.Shader
    if contains_tangent do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr.vert", .VERTEX, allocator) or_return
    else do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr_no_tangent.vert", .VERTEX, allocator) or_return

    id = resource.add_shader(manager, single_shader) or_return
    ok = true
    return
}

@(private)
generate_lighting_frag_shader :: proc(
    manager: ^resource.ResourceManager,
    contains_tangent: bool,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    // Todo dynamic
    dbg.log(.INFO, "Generating lighting frag shader")

    single_shader: resource.Shader
    if contains_tangent do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr.frag", .FRAGMENT, allocator) or_return
    else do single_shader = resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "pbr_no_tangent.frag", .FRAGMENT, allocator) or_return
    id = resource.add_shader(manager, single_shader) or_return
    ok = true
    return
}

@(private)
generate_gbuffer_vertex_shader :: proc(
    manager: ^resource.ResourceManager,
    vertex_layout: ^resource.VertexLayout,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    dbg.log(.INFO, "Generating gbuffer vertex shader")

    shader := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "gbuffer.vert", .VERTEX, allocator) or_return

    defines := make([dynamic]string, allocator=allocator)
    defer delete(defines)

    // I guess two position/normals in the layout info is ub
    for attribute in vertex_layout.infos do #partial switch attribute.type {
        case .position: append_elem(&defines, "#define POSITION_INPUT")
        case .normal: append_elem(&defines, "#define NORMAL_INPUT")
    }
    old_src := shader.source.string_source
    defer delete(old_src)
    shader.source.string_source = resource.add_shader_defines(old_src, ..defines[:], allocator=allocator) or_return

    return resource.add_shader(manager, shader)
}

@(private)
generate_gbuffer_frag_shader :: proc(
    manager: ^resource.ResourceManager,
    generate_config: GBufferShaderGenerateConfig,
    vertex_layout: ^resource.VertexLayout,
    allocator := context.allocator
) -> (id: resource.ResourceIdent, ok: bool) {
    dbg.log(.INFO, "Generating gbuffer frag shader")

    shader := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "gbuffer.frag", .FRAGMENT, allocator) or_return

    defines := make([dynamic]string, allocator=allocator)
    defer delete(defines)

    for attribute in vertex_layout.infos do #partial switch attribute.type {
    case .position: if .POSITION in generate_config.outputs do append_elem(&defines, "#define POSITION_INPUT")
    case .normal: if .NORMAL in generate_config.outputs do append_elem(&defines, "#define NORMAL_INPUT")
    }
    old_src := shader.source.string_source
    defer delete(old_src)
    shader.source.string_source = resource.add_shader_defines(old_src, ..defines[:], allocator=allocator) or_return

    return resource.add_shader(manager, shader)
}


// Generic interface to handle pre-render passes explicitly
// The pre-render pass procedures used inside this don't necessarily need to be only called by this,
//  for example when changing IBL settings, ibl_pre_render_pass is called independent of this procedure
// todo deprecate?
pre_render :: proc(manager: ^resource.ResourceManager, pipeline: RenderPipeline, scene: ^ecs.Scene, temp_allocator := context.temp_allocator) -> (ok: bool) {

    for pass in pipeline.pre_passes {
        if len(pass.frame_buffers) == 0 {
            dbg.log(.ERROR, "Pre render pass must have more than one framebuffer")
            return
        }

        switch input in pass.input {
        case IBLInput:
            ok = ibl_render_setup(manager)
            if !ok {
                dbg.log(.ERROR, "Failed to pre render IBL maps")
                return
            }
        }
    }

    ok = true
    return
}


ImageEnvironment :: struct {
    // All cubemaps, IBL textures: image field is not used
    environment_tex: resource.Texture,
    environment_map: Maybe(resource.Texture),
    //IBL
    irradiance_map: Maybe(resource.Texture),
    prefilter_map: Maybe(resource.Texture),
    brdf_lookup: Maybe(resource.Texture)
}

// Does not create cubemap
make_image_environment :: proc(
    manager: ^resource.ResourceManager,
    environment_map_uri: string,
    env_face_size: Maybe(i32),
    flip_map := false,
    allocator := context.allocator
) -> (ok: bool) {
    env: ImageEnvironment
    using env.environment_tex
    name = strings.clone("EnvironmentTex", allocator=allocator)
    type = .TWO_DIM
    properties = resource.default_texture_properties()
    properties[.WRAP_S] = .REPEAT
    properties[.MIN_FILTER] = .LINEAR_MIPMAP_LINEAR
    image = resource.load_image_from_uri(environment_map_uri, flip_image=flip_map, as_float=true, allocator=allocator) or_return

    transfer_texture(&env.environment_tex, gl.RGB16F, 0, gl.RGBA, gl.FLOAT, true) or_return

    if env_face_size != nil {
        w := env_face_size.?
        // Automatically creates temp framebuffer
        env.environment_map = create_environment_map(manager, w, w, env.environment_tex, environment_project(), cubemap_views(), allocator=allocator) or_return
    }

    Context.image_environment = env

    ok = true
    return
}

// Todo release GPU memory
destroy_image_environment :: proc(environment: Maybe(ImageEnvironment)) {
    if environment == nil do return
    env := environment.?

    resource.destroy_texture(&env.environment_tex)
    if env.environment_map != nil do resource.destroy_texture(&env.environment_map.?)
    if env.irradiance_map != nil do resource.destroy_texture(&env.irradiance_map.?)
    if env.prefilter_map != nil do resource.destroy_texture(&env.prefilter_map.?)
    if env.brdf_lookup != nil do resource.destroy_texture(&env.brdf_lookup.?)
}

destroy_ibl_in_image_environment :: proc(environment: Maybe(ImageEnvironment)) {
    if environment == nil do return
    env := environment.?

    if env.irradiance_map != nil do resource.destroy_texture(&env.irradiance_map.?)
    if env.prefilter_map != nil do resource.destroy_texture(&env.prefilter_map.?)
    if env.brdf_lookup != nil do resource.destroy_texture(&env.brdf_lookup.?)
}


ibl_render_setup :: proc(
    manager: ^resource.ResourceManager,
    allocator := context.allocator,
    loc := #caller_location
) -> (ok: bool) {
    dbg.log(.INFO, "IBL Pre render pass")
    if Context.renderdoc != nil {
        renderdoc := Context.renderdoc.?
        rdoc.StartFrameCapture(renderdoc.api, nil, nil)
    }
    defer if Context.renderdoc != nil {
        renderdoc := Context.renderdoc.?
        rdoc.EndFrameCapture(renderdoc.api, nil, nil)
    }

    ibl_framebuffer := make_ibl_framebuffer(allocator) or_return
    defer destroy_framebuffer(&ibl_framebuffer, release_attachments=false)

    env_settings, env_settings_ok := GlobalRenderSettings.environment_settings.?
    if !env_settings_ok {
        dbg.log(.ERROR, "Environment settings must be available in ibl pre render pass")
        return
    }

    ibl_settings, ibl_settings_ok := env_settings.ibl_settings.?
    if !ibl_settings_ok {
        dbg.log(.ERROR, "IBL settings must be available in ibl pre render pass")
        return
    }

    environment_m := &Context.image_environment
    if environment_m^ == nil {
        dbg.log(.ERROR, "No environment found in scene for IBL")
        return
    }
    environment: ^ImageEnvironment = &environment_m.?

    set_depth_test(true)
    set_depth_func(.LEQUAL)
    gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

    transfer_texture(&environment.environment_tex, gl.RGB16F, 0, gl.RGBA, gl.FLOAT, true) or_return

    cube_comp := create_primitive_cube()
    defer release_gl_component(cube_comp)
    cube_vao := cube_comp.vao.?

    fbo := utils.unwrap_maybe(ibl_framebuffer.id) or_return

    depth_rbo := make_renderbuffer(env_settings.environment_face_size, env_settings.environment_face_size, gl.DEPTH_COMPONENT24)
    rbo := utils.unwrap_maybe(depth_rbo.id) or_return

    bind_renderbuffer_to_frame_buffer(fbo, depth_rbo, .DEPTH)
    check_framebuffer_status(ibl_framebuffer, loc=loc) or_return
    dbg.log(.INFO, "Bound renderbuffer to frame buffer")

    project := environment_project()

    views := cubemap_views()

    if environment.environment_map == nil do environment.environment_map = create_environment_map(
        manager,
        env_settings.environment_face_size,
        env_settings.environment_face_size,
        environment.environment_tex,
        project,
        views,
        fbo,
        cube_vao,
        allocator=allocator
    ) or_return
    check_framebuffer_status(ibl_framebuffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl environment map")

    env_map := environment.environment_map.?
    env_cubemap := env_map.gpu_texture

    if environment.irradiance_map == nil do environment.irradiance_map = create_ibl_irradiance_map(
        manager,
        ibl_settings.irradiance_map_face_size,
        ibl_settings.irradiance_map_face_size,
        env_cubemap,
        project,
        views,
        fbo,
        rbo,
        cube_vao,
        allocator
    ) or_return
    check_framebuffer_status(ibl_framebuffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl irradiance map")


    if environment.prefilter_map == nil do environment.prefilter_map = create_ibl_prefilter_map(
        manager,
        ibl_settings.prefilter_map_face_size,
        ibl_settings.prefilter_map_face_size,
        env_cubemap,
        project,
        views,
        fbo,
        rbo,
        cube_vao,
        allocator
    ) or_return
    check_framebuffer_status(ibl_framebuffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl prefilter map")

    if environment.brdf_lookup == nil do environment.brdf_lookup = create_ibl_brdf_lookup(
        manager,
        ibl_settings.brdf_lut_size,
        ibl_settings.brdf_lut_size,
        fbo,
        rbo,
        allocator
    ) or_return
    check_framebuffer_status(ibl_framebuffer, loc=loc) or_return
    dbg.log(.INFO, "Successfully created ibl brdf lookup table")

    bind_default_framebuffer()

    ok = true
    return
}

environment_project :: proc() -> matrix[4, 4]f32 {
    return glm.mat4Perspective(glm.radians_f32(90), 1, 0.1, 10)
}

// Follows OpenGL orientation order: +X, -X, +Y, -Y, +Z, -Z
cubemap_views :: proc() -> [6]matrix[4, 4]f32 {
    return [6]matrix[4, 4]f32 {
        glm.mat4LookAt({0, 0, 0}, {1, 0, 0}, {0, -1, 0}),
        glm.mat4LookAt({0, 0, 0}, {-1, 0, 0}, {0, -1, 0}),
        glm.mat4LookAt({0, 0, 0}, {0, 1, 0}, {0, 0, 1}),
        glm.mat4LookAt({0, 0, 0}, {0, -1, 0}, {0, 0, -1}),
        glm.mat4LookAt({0, 0, 0}, {0, 0, 1}, {0, -1, 0}),
        glm.mat4LookAt({0, 0, 0}, {0, 0, -1}, {0, -1, 0}),
    }
}

create_environment_map :: proc(
    manager: ^resource.ResourceManager,
    env_map_face_w, env_map_face_h: i32,
    environment_tex: resource.Texture,
    project: matrix[4, 4]f32,
    views: [6]matrix[4, 4]f32,
    fbo: Maybe(u32) = nil,
    cube_vao: Maybe(u32) = nil,
    allocator := context.allocator
) -> (env: resource.Texture, ok: bool) {

    fbo_id: u32
    cube_vao_id: u32

    // Create framebuffer if not given
    created_framebuffer: ^FrameBuffer
    if fbo == nil {
        created_framebuffer = new(FrameBuffer)
        created_framebuffer^ = make_framebuffer(env_map_face_w, env_map_face_h, allocator)
        fbo_id = created_framebuffer.id.?
    }
    else do fbo_id = fbo.?
    defer if created_framebuffer != nil {
        destroy_framebuffer(created_framebuffer, release_attachments=false)
        free(created_framebuffer)
    }

    // Create cube if not given
    created_cube: ^resource.GLComponent
    if cube_vao == nil {
        created_cube = new(resource.GLComponent)
        created_cube^ = create_primitive_cube()
        cube_vao_id = created_cube.vao.?
    }
    else do cube_vao_id = cube_vao.?
    defer if created_cube != nil {
        release_gl_component(created_cube^)
        free(created_cube)
    }

    using env
    name = strings.clone("EnvironmentMap", allocator=allocator)

    properties = resource.default_texture_properties()
    properties[.MIN_FILTER] = .LINEAR_MIPMAP_LINEAR

    gpu_texture = make_texture(env_map_face_w, env_map_face_h, nil, gl.RGB16F, 0, gl.RGB, gl.FLOAT, resource.TextureType.CUBEMAP, properties, false)
    type = .CUBEMAP

    shader := get_environment_map_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    resource.set_uniform(&shader, "environmentTex", i32(0))
    resource.set_uniform(&shader, "m_Project", project)
    bind_texture(0, environment_tex.gpu_texture) or_return

    set_render_viewport(0, 0, env_map_face_w, env_map_face_h)

    gl.Disable(gl.DEPTH_TEST)
    gl.Disable(gl.BLEND)
    gl.Disable(gl.CULL_FACE)
    gl.Disable(gl.MULTISAMPLE)

    bind_framebuffer_raw(fbo_id)
    for i in 0..<6 {
        resource.set_uniform(&shader, "m_View", views[i])
        bind_texture_to_frame_buffer(fbo_id, env, .COLOUR, u32(i), 0, 0) or_return
        clear_mask({ .COLOUR_BIT, .DEPTH_BIT })

        render_primitive_cube(cube_vao_id)

        detach_from_framebuffer(fbo_id, env.type, .COLOUR, u32(i), 0)
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

create_ibl_irradiance_map :: proc(
    manager: ^resource.ResourceManager,
    irradiance_map_face_w, irradiance_map_face_h: i32,
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
    gpu_texture = make_texture(irradiance_map_face_w, irradiance_map_face_w, nil, gl.RGB16F, 0, gl.RGB, gl.FLOAT, resource.TextureType.CUBEMAP, properties, false)
    type = .CUBEMAP

    bind_framebuffer_raw(fbo)
    bind_renderbuffer_raw(rbo)
    set_render_buffer_storage(gl.DEPTH_COMPONENT24, irradiance_map_face_w, irradiance_map_face_h)

    shader := get_ibl_irradiance_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    resource.set_uniform(&shader, "environmentMap", i32(0))
    resource.set_uniform(&shader, "m_Project", project)
    bind_texture(0, env_cubemap, .CUBEMAP) or_return

    set_render_viewport(0, 0, irradiance_map_face_w, irradiance_map_face_h)
    bind_framebuffer_raw(fbo)
    for i in 0..<6 {
        resource.set_uniform(&shader, "m_View", views[i])
        bind_texture_to_frame_buffer(fbo, irradiance, .COLOUR, cube_face=u32(i), attachment_loc=0)
        clear_mask({ .COLOUR_BIT, .DEPTH_BIT })

        draw_buffers(gl.COLOR_ATTACHMENT0)
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

create_ibl_prefilter_map :: proc(
    manager: ^resource.ResourceManager,
    prefilter_map_face_w, prefilter_map_face_h: i32,
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
    gpu_texture = make_texture(prefilter_map_face_w, prefilter_map_face_h, nil, gl.RGB16F, 0, gl.RGB, gl.FLOAT, resource.TextureType.CUBEMAP, properties, true)
    type = .CUBEMAP

    shader := get_ibl_prefilter_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    resource.set_uniform(&shader, "environmentMap", i32(0))
    resource.set_uniform(&shader, "m_Project", project)
    bind_texture(0, env_cubemap, .CUBEMAP) or_return

    gl.Enable(gl.DEPTH_TEST)
    // gl.CullFace(gl.FRONT)
    gl.Disable(gl.STENCIL_TEST)

    bind_framebuffer_raw(fbo)
    check_framebuffer_status_raw() or_return
    MIP_LEVELS :: 5
    for mip in 0..<MIP_LEVELS {

        mip_width := i32(f32(prefilter_map_face_w) * math.pow(0.5, f32(mip)))
        mip_height := i32(f32(prefilter_map_face_h) * math.pow(0.5, f32(mip)))

        dbg.log(.INFO, "Mip w: %d, h: %d", mip_width, mip_height)

        bind_renderbuffer_raw(rbo)
        set_render_buffer_storage(gl.DEPTH_COMPONENT24, mip_width, mip_height)
        check_framebuffer_status_raw() or_return

        set_render_viewport(0, 0, mip_width, mip_height)

        roughness: f32 = f32(mip) / f32(MIP_LEVELS - 1)
        resource.set_uniform(&shader, "roughness", roughness)

        for i in 0..<6 {
            resource.set_uniform(&shader, "m_View", views[i])
            bind_texture_to_frame_buffer(fbo, prefilter, .COLOUR, cube_face=u32(i), attachment_loc=0, mip_level=i32(mip))
            check_framebuffer_status_raw() or_return

            clear_mask({ .COLOUR_BIT, .DEPTH_BIT })
            draw_buffers(gl.COLOR_ATTACHMENT0)

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

create_ibl_brdf_lookup :: proc(
    manager: ^resource.ResourceManager,
    brdf_lut_w, brdf_lut_h: i32,
    fbo: u32,
    rbo: u32,
    allocator := context.allocator
) -> (brdf_lut: resource.Texture, ok: bool) {
    using brdf_lut
    name = strings.clone("BrdfLUT", allocator=allocator)
    properties = resource.default_texture_properties(allocator)
    gpu_texture = make_texture(brdf_lut_w, brdf_lut_h, nil, gl.RG16, 0, gl.RG, gl.FLOAT, resource.TextureType.TWO_DIM, properties, false)
    type = .TWO_DIM

    shader := get_ibl_brdf_lut_shader(manager, allocator) or_return
    defer resource.destroy_shader_program(manager, shader)

    bind_framebuffer_raw(fbo)
    bind_renderbuffer_raw(rbo)
    set_render_buffer_storage(gl.DEPTH_COMPONENT24, brdf_lut_w, brdf_lut_h)
    bind_texture_to_frame_buffer(fbo, brdf_lut, .COLOUR)

    set_render_viewport(0, 0, brdf_lut_w, brdf_lut_h)
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

make_ibl_framebuffer :: proc(allocator := context.allocator) -> (buffer: FrameBuffer, ok: bool) {
    settings, env_ok := GlobalRenderSettings.environment_settings.?
    if !env_ok {
        dbg.log(.ERROR, "Environment settings must be available to create IBL framebuffer")
        return
    }

    return make_framebuffer(settings.environment_face_size, settings.environment_face_size, allocator=allocator), true
}

// Just using learnopengl here, obviously using indexed would be better, but marginally so
create_primitive_cube_mesh :: proc(manager: ^resource.ResourceManager) -> (mesh: resource.Mesh, ok: bool) {
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


    comp: resource.GLComponent
    create_and_transfer_vao(&comp.vao)
    verts_dyn := transmute([dynamic]f32)runtime.Raw_Dynamic_Array{ &verts[0], len(verts), len(verts), context.allocator }
    layout := []resource.MeshAttributeInfo{
        resource.MeshAttributeInfo{ .position, .vec3, .f32, 12, 3, "" },
        resource.MeshAttributeInfo{ .normal, .vec2, .f32, 12, 3, "" },
        resource.MeshAttributeInfo{ .texcoord, .vec2, .f32, 8, 2, "" },
    }
    create_and_transfer_vbo_maybe(&comp.vbo, verts_dyn, layout)

    mesh.gl_component = comp
    mesh.centroid = resource.calculate_centroid(verts_dyn, layout) or_return
    mesh.vertices_count = 36
    mesh.layout = resource.add_vertex_layout(manager, resource.VertexLayout{ infos=layout }) or_return
    mesh.material.type = resource.add_material(manager, resource.MaterialType{ unlit = true }) or_return
    mesh.render_type = .TRIANGLES

    return
}

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


// todo fix vertex layout
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

// Position, texcoord are available
create_primitive_quad_mesh :: proc(manager: ^resource.ResourceManager) -> (mesh: resource.Mesh, ok: bool) {
    verts := [5 * 4]f32 {
        -1,  1, 0,  0, 1,
        1,  1, 0,  1, 1,
        -1, -1, 0,  0, 0,
        1, -1, 0,  1, 0,
    }

    comp: resource.GLComponent
    create_and_transfer_vao(&comp.vao)
    verts_dyn := transmute([dynamic]f32)runtime.Raw_Dynamic_Array{ &verts[0], len(verts), len(verts), context.allocator }
    layout := []resource.MeshAttributeInfo{
        resource.MeshAttributeInfo{ .position, .vec3, .f32, 12, 3, "" },
        resource.MeshAttributeInfo{ .texcoord, .vec2, .f32, 8, 2, "" },
    }
    create_and_transfer_vbo_maybe(&comp.vbo, verts_dyn, layout)

    mesh.gl_component = comp
    mesh.centroid = resource.calculate_centroid(verts_dyn, layout) or_return
    mesh.vertices_count = 4
    mesh.layout = resource.add_vertex_layout(manager, resource.VertexLayout{ infos=layout }) or_return
    mesh.material.type = resource.add_material(manager, resource.MaterialType{ unlit = true }) or_return
    mesh.render_type = .TRIANGLE_STRIP

    return
}
