package render

import "../ecs"
import "../resource"
import "../shader"
import "../utils"
import dbg "../debug"
import "../standards"
import lutils "../utils/linalg_utils"
import cam "../camera"

import "core:strings"
import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:log"


RenderContext :: struct {
    camera_ubo: ^ShaderBuffer,
    lights_ssbo: ^ShaderBuffer
}

RENDER_CONTEXT: RenderContext  // Global render context, this is fine really, only stores small amount of persistent external pointing data


render :: proc(manager: ^resource.ResourceManager, pipeline: RenderPipeline, scene: ^ecs.Scene) -> (ok: bool) {

    /*
        for later:
            instancing done via InstanceTo ecs component
            batching via combining entities with matching gpu components
    */

    // query scene for renderable models
    isVisibleQueryData := true
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = resource.MODEL_COMPONENT.label, action = .QUERY_AND_INCLUDE },
        { label = standards.WORLD_COMPONENT.label, action = .NO_QUERY_BUT_INCLUDE },
        { label = standards.VISIBLE_COMPONENT.label, action = .QUERY_NO_INCLUDE, data = &isVisibleQueryData },
    }}
    query_result := ecs.query_scene(scene, query) or_return

    // flatten into lots of meshes
    ModelWorldPair :: struct {
        model: ^resource.Model,
        world_comp: ^standards.WorldComponent
    }
    model_data: [dynamic]ModelWorldPair = make([dynamic]ModelWorldPair, context.temp_allocator)

    for _, arch_result in query_result {
        models: []^resource.Model
        world_comps: []^standards.WorldComponent
        for comp_label, comp_ind in arch_result.component_map {
            switch comp_label {
            case resource.MODEL_COMPONENT.label:
                models = ecs.components_deserialize_raw(resource.Model, arch_result.data[comp_ind]) or_return
            case standards.WORLD_COMPONENT.label:
                world_comps = ecs.components_deserialize_raw(standards.WorldComponent, arch_result.data[comp_ind]) or_return
            }
        }

        if len(models) != len(world_comps) {
            dbg.log(.ERROR, "Received unbalanced input from scene query")
            return
        }
        for i in 0..<len(models) {
            append(&model_data, ModelWorldPair{ models[i], world_comps[i]})
        }

    }

    if len(pipeline.passes) == 1 && pipeline.passes[0].type == .LIGHTING {
        // Render to default framebuffer directly
        // Make single element draw call per mesh
        ok = create_lighting_shader(manager, true)
        if !ok {
            dbg.log(.ERROR, "Lighting shader failed to create")
            return
        }

        // Group draw calls by material to reduce shader context changes
        MeshWorldPair :: struct {
            mesh: ^resource.Mesh,
            world_comp: ^standards.WorldComponent
        }

        material_map := make(map[resource.ResourceIdent][dynamic]MeshWorldPair, context.temp_allocator)
        defer {
            for _, v in material_map do delete(v)
            delete(material_map)
        }

        for &model_pair in model_data {
            for &mesh in model_pair.model.meshes {
                mat_id, mat_ok := mesh.material.?; if !mat_ok {
                    dbg.log(.ERROR, "Material not found for mesh")
                    return
                }

                pair := MeshWorldPair{ &mesh, model_pair.world_comp }
                if mat_id in material_map {
                    dyn := &material_map[mat_id]
                    append(dyn, pair)
                }
                else {
                    dyn := make([dynamic]MeshWorldPair, 1, context.temp_allocator)
                    dyn[0] = pair
                    material_map[mat_id] = dyn
                }

            }
        }

        for mat_id, &mesh_pairs in material_map {

            material := resource.get_material(manager, mat_id) or_return

            // Sanity checks
            if material == nil {
                dbg.log(.ERROR, "Material does not exist for material id")
                return
            }
            if material.lighting_shader == nil {
                dbg.log(.ERROR, "Material lighting shader is not set")
            }

            lighting_shader := resource.get_shader(manager, material.lighting_shader.?) or_return

            if lighting_shader.id == nil {
                dbg.log(.INFO, "Compiling and transferring lighting shader in render")
                transfer_shader(lighting_shader) or_return
                return
            }

            bind_program(lighting_shader.id.?)
            bind_material_uniforms(manager, material^, lighting_shader) or_return
            update_camera_ubo(scene) or_return
            update_lights_ssbo(scene) or_return

            for &mesh_pair in mesh_pairs {
                model_mat, normal_mat := model_and_normal(mesh_pair.mesh, mesh_pair.world_comp, scene.viewpoint)
                transfer_mesh(mesh_pair.mesh) or_return

                shader.set_uniform(lighting_shader, standards.MODEL_MAT, model_mat)
                shader.set_uniform(lighting_shader, standards.NORMAL_MAT, normal_mat)

                issue_single_element_draw_call(mesh_pair.mesh.indices_count)
            }
        }
    }
    else {
        // figure it out when the need is there
    }

    return true
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
bind_material_uniforms :: proc(manager: ^resource.ResourceManager, material: resource.Material, lighting_shader: ^shader.ShaderProgram) -> (ok: bool) {

    texture_unit: u32
    infos: resource.MaterialPropertiesInfos
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
                shader.set_uniform(lighting_shader, resource.BASE_COLOUR_TEXTURE, i32(texture_unit))
                texture_unit += 1

                transfer_texture(metallic_roughness)
                bind_texture(texture_unit, metallic_roughness.gpu_texture) or_return
                shader.set_uniform(lighting_shader, resource.PBR_METALLIC_ROUGHNESS, i32(texture_unit))
                texture_unit += 1

                shader.set_uniform(lighting_shader, resource.BASE_COLOUR_FACTOR, v.base_colour_factor[0], v.base_colour_factor[1], v.base_colour_factor[2], v.base_colour_factor[3])
                shader.set_uniform(lighting_shader, resource.METALLIC_FACTOR, v.metallic_factor)
                shader.set_uniform(lighting_shader, resource.ROUGHNESS_FACTOR, v.roughness_factor)

            case resource.EmissiveFactor:
                shader.set_uniform(lighting_shader, resource.EMISSIVE_FACTOR, v[0], v[1], v[2])

            case resource.EmissiveTexture:
                emissive_texture, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || emissive_texture == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Emissive texture unavailable")
                    return
                }

                transfer_texture(emissive_texture)
                bind_texture(texture_unit, emissive_texture.gpu_texture.?) or_return
                shader.set_uniform(lighting_shader, resource.EMISSIVE_TEXTURE, i32(texture_unit))
                texture_unit += 1

            case resource.OcclusionTexture:
                occlusion_texture, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || occlusion_texture == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Occlusion texture unavailable")
                    return
                }

                transfer_texture(occlusion_texture)
                bind_texture(texture_unit, occlusion_texture.gpu_texture.?) or_return
                shader.set_uniform(lighting_shader, resource.OCCLUSION_TEXTURE, i32(texture_unit))
                texture_unit += 1

            case resource.NormalTexture:
                normal_texture, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || normal_texture  == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Normal texture unavailable")
                    return
                }

                transfer_texture(normal_texture)
                bind_texture(texture_unit, normal_texture.gpu_texture.?) or_return
                shader.set_uniform(lighting_shader, resource.NORMAL_TEXTURE, i32(texture_unit))
                texture_unit += 1
            case resource.BaseColourTexture:
                base_colour, tex_ok := resource.get_texture(manager, resource.ResourceIdent(v))
                if !tex_ok || base_colour == nil {
                    dbg.log(dbg.LogLevel.ERROR, "Base colour texture unavailable")
                    return
                }

                transfer_texture(base_colour)
                bind_texture(texture_unit, base_colour.gpu_texture) or_return
                shader.set_uniform(lighting_shader, resource.BASE_COLOUR_TEXTURE, i32(texture_unit))
                texture_unit += 1

        }
    }

    // shader.set_uniform(lighting_shader, resource.MATERIAL_INFOS, transmute(u32)infos)
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
    isVisibleQueryData := true
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = resource.LIGHT_COMPONENT.label, action = .QUERY_AND_INCLUDE },
        { label = standards.VISIBLE_COMPONENT.label, action = .QUERY_NO_INCLUDE, data = &isVisibleQueryData }
    }}
    query_result := ecs.query_scene(scene, query) or_return

    lights := ecs.get_component_from_query_result(query_result, resource.Light, resource.LIGHT_COMPONENT.label) or_return

    spot_lights := make([dynamic]^resource.SpotLight)
    directional_lights := make([dynamic]^resource.DirectionalLight)
    point_lights := make([dynamic]^resource.PointLight)

    for &light in lights do switch &v in light {
        case resource.SpotLight: append(&spot_lights, &v)
        case resource.DirectionalLight: append(&directional_lights, &v)
        case resource.PointLight: append(&point_lights, &v)
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


// todo full - this is demo
create_lighting_shader :: proc(manager: ^resource.ResourceManager, compile: bool) -> (ok: bool) {
    materials := resource.get_materials(manager^)
    defer delete(materials)

    for material in materials {
        if material.lighting_shader != nil do continue

        dbg.log(dbg.LogLevel.INFO, "Creating lighing shader for material: %s", material.name)
        program := shader.read_shader_source(standards.SHADER_RESOURCE_PATH + "demo_shader.frag", standards.SHADER_RESOURCE_PATH + "demo_shader.vert") or_return
        if compile do transfer_shader(&program) or_return

        shader_id := resource.add_shader(manager, program) or_return
        material.lighting_shader = shader_id
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
) -> (vertex: shader.ShaderInfo, frag: shader.ShaderInfo, ok: bool) {

    // Add input bindings
    shader_layout_from_mesh_layout(&vertex, attribute_infos) or_return

    //Lights
    light_struct := shader.make_shader_struct("Light",
        { shader.GLSLDataType.vec3, "colour", }, { shader.GLSLDataType.vec3, "position" }
    )
    shader.add_structs(&frag, light_struct)

    shader.add_bindings_of_type(&frag, .SSBO, {
        "lights",
        []shader.ExtendedGLSLPair{
            {
                shader.GLSLVariableArray { "Light" },
                "lights"
            }
        }
    })


    vertex_source := make([dynamic]string)
    defer shader.destroy_function_source(vertex_source[:])

    /*
    // Add shader input/output for both vertex and fragment
    for attribute_info in attribute_infos {
        input_pair := shader.GLSLPair{ glsl_type_from_attribute(attribute_info) or_return, attribute_info.name}
        shader.add_outputs(&vertex, input_pair)
        shader.add_inputs(&frag, input_pair)

        assign_to: string
        defer delete(assign_to)

        if type, type_ok := input_pair.type.(shader.GLSLDataType); type_ok {
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
    shader.add_uniforms(&vertex,
        { .mat4, MODEL_MATRIX_UNIFORM },
        { .mat4, VIEW_MATRIX_UNIFORM },
        { .mat4, PROJECTION_MATRIX_UNIFORM },
        { .mat4, NORMAL_MATRIX_UNIFORM }
    )

    // Add vertex main function
    utils.fmt_append(&vertex_source, "gl_Position = %s * %s * vec4(%s, 1.0);", PROJECTION_MATRIX_UNIFORM, VIEW_MATRIX_UNIFORM, "position")

    main_func := shader.make_shader_function(.void, "main", vertex_source[:])
    shader.add_functions(&vertex, main_func)

    // Frag uniforms
    if .NORMAL_TEXTURE not_in material.properties {
        dbg.debug_point(dbg.LogLevel.ERROR, "Normal map must be available in the material for lighting")
        return
    }

    if .PBR_METALLIC_ROUGHNESS not_in material.properties {
        dbg.debug_point(dbg.LogLevel.ERROR, "PBR Metallic Roughness map must be available in the material for lighting")
        return
    }

    uniforms := make([dynamic]shader.GLSLPair); defer shader.destroy_glsl_pairs(uniforms[:])

    // todo
    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.BASE_COLOUR_TEXTURE })  // base colour comes from pbrMetallicRoughness
    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.PBR_METALLIC_ROUGHNESS })
    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.NORMAL_TEXTURE })

    inc_emissive_texture := .EMISSIVE_TEXTURE in material.properties
    inc_occlusion_texture := .OCCLUSION_TEXTURE in material.properties

    if inc_emissive_texture {
        append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.EMISSIVE_TEXTURE })
        append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.vec3, resource.EMISSIVE_FACTOR })
    }

    if inc_occlusion_texture do append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.OCCLUSION_TEXTURE })

    */


    ok = true
    return
}

MODEL_MATRIX_UNIFORM :: "m_Model"
VIEW_MATRIX_UNIFORM :: "m_View"
PROJECTION_MATRIX_UNIFORM :: "m_Projection"
