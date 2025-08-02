package render

import "../ecs"
import "../resource"
import "../utils"
import dbg "../debug"
import "../standards"
import lutils "../utils/linalg_utils"
import cam "../camera"

import "core:slice"
import "core:strings"
import "core:fmt"
import "base:runtime"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:log"




RenderContext :: struct {
    camera_ubo: ^ShaderBuffer,
    lights_ssbo: ^ShaderBuffer
}

RENDER_CONTEXT: RenderContext  // Global render context, this is fine really, only stores small amount of persistent external pointing data

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

render :: proc(manager: ^resource.ResourceManager, pipeline: RenderPipeline($N), scene: ^ecs.Scene, temp_allocator := context.temp_allocator) -> (ok: bool) {

    /*
        for later:
            instancing done via InstanceTo ecs component
    */

    if len(pipeline.passes) == 0 {
        dbg.log(.ERROR, "No passes to render")
        return
    }


    // todo design system of resource transfer

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
                mesh_data_map[&pass] = query_scene(manager, scene, v, temp_allocator) or_return
                mesh_data = &mesh_data_map[&pass]
            case nil:
                mesh_data_map[&pass] = query_scene(manager, scene, {}, temp_allocator) or_return
                mesh_data = &mesh_data_map[&pass]

        }

        if pass.properties.geometry_z_sorting != .NO_SORT do sort_geometry_by_depth(mesh_data[:], pass.properties.geometry_z_sorting == .ASC)

        // Group geometry by shaders
        shader_map := group_meshes_by_shader(mesh_data^, temp_allocator)

        handle_pass_properties(pipeline, pass)

        // render meshes
        for shader_pass_id, &mesh_datas  in shader_map {

            shader_pass := resource.get_shader_pass(manager, shader_pass_id) or_return

            // Sanity checks
            if shader_pass == nil {
                dbg.log(.ERROR, "Shader pass does not exist for material id")
                return
            }

            if shader_pass.id == nil {
                dbg.log(.ERROR, "Shader pass is not yet compiled before render")
                return
            }

            bind_program(shader_pass.id.?)
            update_camera_ubo(scene) or_return
            update_lights_ssbo(scene) or_return

            for &mesh_data in mesh_datas {
                model_mat, normal_mat := model_and_normal(mesh_data.mesh, mesh_data.world, scene.viewpoint)
                transfer_mesh(manager, mesh_data.mesh) or_return

                bind_material_uniforms(manager, mesh_data.mesh.material, shader_pass) or_return
                resource.set_uniform(shader_pass, standards.MODEL_MAT, model_mat)
                resource.set_uniform(shader_pass, standards.NORMAL_MAT, normal_mat)

                issue_single_element_draw_call(mesh_data.mesh.indices_count)
            }
        }
    }


    return true
}

@(private)
group_meshes_by_shader :: proc(meshes: [dynamic]MeshData, temp_allocator := context.temp_allocator) -> (shader_map: map[resource.ResourceIdent][dynamic]MeshData) {

    shader_map = make(map[resource.ResourceIdent][dynamic]MeshData, allocator=temp_allocator)


    for &mesh_data in meshes {
        id := mesh_data.mesh.shader_pass
        if id == nil {
            dbg.log(.ERROR, "Mesh has no assigned shader pass pre render")
            return
        }
        shader_id := id.?

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

    return
}


// Handles binding of framebuffer along with enabling of certain settings/tests
@(private)
handle_pass_properties :: proc(pipeline: RenderPipeline($N), pass: RenderPass) {
    if pass.frame_buffer == nil {
        bind_default_framebuffer()
    } else do bind_framebuffer(pipeline.frame_buffers[pass.frame_buffer.?])

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
        set_blend_func(properties.blend_func.?)
    } else do set_default_blend_func()

    if properties.face_culling != nil {
        cull_geometry_faces(properties.face_culling.?)
    } else do set_face_culling(false)

    if properties.polygon_mode != nil {
        set_polygon_mode(properties.polygon_mode.?)
    } else do set_default_polygon_mode()

}


@(private)
sort_geometry_by_depth :: proc(models_data: []MeshData, z_asc: bool) {
    sort_proc := z_asc ? proc(a: MeshData, b: MeshData) -> bool {
        return a.world.position.z < b.world.position.z
    } : proc(a: MeshData, b: MeshData) -> bool {
        return a.world.position.z > b.world.position.z
    }
    slice.sort_by(models_data, sort_proc)
}


@(private)
query_scene :: proc(
    manager: ^resource.ResourceManager,
    scene: ^ecs.Scene,
    pass_query: RenderPassQuery,
    temp_allocator: mem.Allocator
) -> (mesh_data: [dynamic]MeshData, ok: bool) {

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
    model = standards.model_from_world_component(world_comp)
    normal = lutils.normal_mat(model)
    return
}

/*
    Specifically used in respect to the lighting shader stored inside the material
*/
@(private)
bind_material_uniforms :: proc(manager: ^resource.ResourceManager, material: resource.Material, lighting_shader: ^resource.ShaderProgram) -> (ok: bool) {

    texture_unit: u32
    infos: resource.MaterialPropertyInfos
    for info, property in material.properties {
        infos += { info }
        switch v in property.value {
            case resource.PBRMetallicRoughness:
                base_colour := resource.get_texture(manager, v.base_colour) or_return
                if base_colour == nil {
                    dbg.log(dbg.LogLevel.ERROR, "PBR Metallic Roughness base colour texture unavailable")
                    return
                }
                metallic_roughness := resource.get_texture(manager, v.metallic_roughness) or_return
                if metallic_roughness == nil {
                    dbg.log(dbg.LogLevel.ERROR, "PBR Metallic Roughness metallic roughness texture unavailable")
                    return
                }

                transfer_texture(base_colour)
                bind_texture(texture_unit, base_colour.gpu_texture) or_return
                resource.set_uniform(lighting_shader, resource.BASE_COLOUR_TEXTURE, i32(texture_unit))
                texture_unit += 1

                transfer_texture(metallic_roughness)
                bind_texture(texture_unit, metallic_roughness.gpu_texture) or_return
                resource.set_uniform(lighting_shader, resource.PBR_METALLIC_ROUGHNESS, i32(texture_unit))
                texture_unit += 1

                resource.set_uniform(lighting_shader, resource.BASE_COLOUR_FACTOR, v.base_colour_factor[0], v.base_colour_factor[1], v.base_colour_factor[2], v.base_colour_factor[3])
                resource.set_uniform(lighting_shader, resource.METALLIC_FACTOR, v.metallic_factor)
                resource.set_uniform(lighting_shader, resource.ROUGHNESS_FACTOR, v.roughness_factor)

            case resource.EmissiveFactor:
                resource.set_uniform(lighting_shader, resource.EMISSIVE_FACTOR, v[0], v[1], v[2])

            case resource.EmissiveTexture:
                emissive_texture, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || emissive_texture == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Emissive texture unavailable")
                    return
                }

                transfer_texture(emissive_texture)
                bind_texture(texture_unit, emissive_texture.gpu_texture.?) or_return
                resource.set_uniform(lighting_shader, resource.EMISSIVE_TEXTURE, i32(texture_unit))
                texture_unit += 1

            case resource.OcclusionTexture:
                occlusion_texture, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || occlusion_texture == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Occlusion texture unavailable")
                    return
                }

                transfer_texture(occlusion_texture)
                bind_texture(texture_unit, occlusion_texture.gpu_texture.?) or_return
                resource.set_uniform(lighting_shader, resource.OCCLUSION_TEXTURE, i32(texture_unit))
                texture_unit += 1

            case resource.NormalTexture:
                normal_texture, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || normal_texture  == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Normal texture unavailable")
                    return
                }

                transfer_texture(normal_texture)
                bind_texture(texture_unit, normal_texture.gpu_texture.?) or_return
                resource.set_uniform(lighting_shader, resource.NORMAL_TEXTURE, i32(texture_unit))
                texture_unit += 1
            case resource.BaseColourTexture:
                base_colour, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || base_colour == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Base colour texture unavailable")
                    return
                }

                transfer_texture(base_colour)
                bind_texture(texture_unit, base_colour.gpu_texture) or_return
                resource.set_uniform(lighting_shader, resource.BASE_COLOUR_TEXTURE, i32(texture_unit))
                texture_unit += 1
        }
    }

    // resource.set_uniform(lighting_shader, resource.MATERIAL_INFOS, transmute(u32)infos)
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


// Creates and compiles any shaders attached to VertexLayout or MaterialType resources
create_shaders :: proc(manager: ^resource.ResourceManager, compile := true, shader_allocator := context.allocator) -> (ok: bool) {
    // When this needs to be dynamic, it needs to loop via meshes to get matching pairs of materials and layouts

    materials := resource.get_materials(manager^); defer delete(materials)
    vertex_layouts := resource.get_vertex_layouts(manager^); defer delete(vertex_layouts)

    for &material in materials {
        if material.shader == nil {
            // todo dynamically create
            dbg.log(dbg.LogLevel.INFO, "Creating lighing shader for material")
            single_shader := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "demo_shader.frag", .FRAGMENT, shader_allocator) or_return
            if compile do compile_shader(&single_shader) or_return

            shader_id := resource.add_shader(manager, single_shader) or_return
            material.shader = shader_id
        }
    }

    for &layout in vertex_layouts {
        if layout.shader == nil {
            // todo dynamically create
            dbg.log(dbg.LogLevel.INFO, "Creating vertex shader for layout")
            single_shader := resource.read_single_shader_source(standards.SHADER_RESOURCE_PATH + "demo_shader.vert", .VERTEX, shader_allocator) or_return
            if compile do compile_shader(&single_shader) or_return

            shader_id := resource.add_shader(manager, single_shader) or_return
            layout.shader = shader_id
        }
    }

    return true
}

// Combines shaders from vertex layouts and material types into shader passes (shader programs)
// Compiles any shaders not yet compiled
// Links shaders
// Allocates any memory via allocator
create_shader_passes :: proc(manager: ^resource.ResourceManager, scene: ^ecs.Scene, allocator := context.allocator) -> (ok: bool) {

    // Query scene for all models and flatten to meshes
    isVisibleQueryData := true
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = resource.MODEL_COMPONENT.label, action = .QUERY_AND_INCLUDE },
        { label = standards.VISIBLE_COMPONENT.label, action = .QUERY_NO_INCLUDE, data = &isVisibleQueryData }
    }}
    query_result := ecs.query_scene(scene, query, allocator) or_return
    defer ecs.destroy_scene_query_result(query_result)

    models := ecs.get_component_from_query_result(query_result, resource.Model, resource.MODEL_COMPONENT.label, allocator) or_return
    defer delete(models)

    for &model in models {
        for &mesh in model.meshes {
            layout := resource.get_vertex_layout(manager, mesh.layout) or_return
            material := resource.get_material(manager, mesh.material.type) or_return

            vert := resource.get_shader(manager, layout.shader) or_return
            frag := resource.get_shader(manager, material.shader) or_return

            shaders := make([]resource.Shader, 2, allocator=allocator)
            shaders[0] = vert^
            shaders[1] = frag^

            program := resource.make_shader_program(manager, shaders, allocator) or_return
            transfer_shader_program(manager, &program) or_return
            mesh.shader_pass = resource.add_shader_pass(manager, program) or_return
        }
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
