package render

import "../ecs"
import "../resource"
import "../shader"
import "../utils"
import dbg "../debug"
import "../standards"

import "core:strings"
import "core:fmt"
import glm "core:math/linalg/glsl"
import camera "../camera"

POINT_LIGHT_COMPONENT := standards.ComponentTemplate{ "PointLight", PointLight }
DIRECTIONAL_LIGHT_COMPONENT := standards.ComponentTemplate{ "DirectionalLight", DirectionalLight }
SPOT_LIGHT_COMPONENT := standards.ComponentTemplate{ "SpotLight", SpotLight }

RenderContext :: struct {
    camera_ubo: ^ShaderBuffer,
    light_ubo: ^ShaderBuffer
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
        { label = resource.MODEL_COMPONENT.label, include = true },
        { label = standards.WORLD_COMPONENT.label, include = true },
        { label = standards.VISIBLE_COMPONENT.label, data = &isVisibleQueryData }
    }}
    query_result := ecs.query_scene(scene, query) or_return

    // flatten into lots of meshes
    ModelWorldPair :: struct {
        model: ^resource.Model,
        world_comp: ^standards.WorldComponent
    }
    model_data: [dynamic]ModelWorldPair = make([dynamic]ModelWorldPair)

    for _, arch_result in query_result {
        model_data: []^resource.Model
        world_comps: []^standards.WorldComponent
        for comp_label, comp_ind in arch_result.component_map {
            switch comp_label {
            case resource.MODEL_COMPONENT.label:
                model_data = ecs.components_deserialize_raw(resource.Model, arch_result.data[comp_ind])
            case standards.WORLD_COMPONENT.label:
                world_comps = ecs.components_deserialize_raw(standards.WorldComponent, arch_result.data[comp_ind])
            }

        }
        for i in 0..<len(model_data) {
            append(&model_data, ModelWorldPair{ model_data[i], world_comps[i] })
        }

    }


    // todo do create shader
    // for now assume it works

    if len(pipeline.passes) == 1 && pipelines.passes[0].type == .LIGHTING {
        // Render to default framebuffer directly
        // Make single element draw call per mesh

        // todo group calls by material

        for &model_pair in model_data {
            model_mat := standards.model_from_world_component(model_pair.world_comp^)
            for &mesh in model_pair.model.meshes {
                transfer_mesh(manager, mesh, true, true)

                material := resource.get_material(manager, mesh.material)
                lighting_shader := bind_material_uniforms(manager, material)
                update_camera_ubo(scene)

                shader.set_uniform(lighting_shader, standards.MODEL_MAT, model_mat)

                issue_single_element_draw_call(len(mesh.index_data))
            }
        }
    }
    else {
        // figure it out when the need is there
    }

    return true
}

/*
    Specifically used in respect to the lighting shader stored inside the material
*/
@(private)
bind_material_uniforms :: proc(manager: ^resource.ResourceManager, material: resource.Material) -> (lighting_shader: ^shader.ShaderProgram) {
    lighting_shader = resource.get_shader(manager, material.lighting_shader.?)

    texture_unit := 0
    infos: resource.MaterialPropertiesInfos
    for info, property in material.properties {
        infos += info
        switch v in property {
            case resource.PBRMetallicRoughness:
                base_colour := resource.get_texture(manager, v.base_colour)
                bind_texture(texture_unit, base_colour.gpu_texture.?)
                shader.set_uniform(&lighting_shader, resource.BASE_COLOUR_TEXTURE, texture_unit)
                texture_unit += 1

                metallic_roughness := resource.get_texture(manager, v.metallic_roughness)
                bind_texture(texture_unit, metallic_roughness.gpu_texture.?)
                shader.set_uniform(&lighting_shader, resource.PBR_METALLIC_ROUGHNESS, texture_unit)
                texture_unit += 1

                shader.set_uniform(&lighting_shader, resource.BASE_COLOUR_FACTOR, v.base_colour_factor)
                shader.set_uniform(&lighting_shader, resource.METALLIC_FACTOR, v.metallic_factor)
                shader.set_uniform(&lighting_shader, resource.ROUGHNESS_FACTOR, v.roughness_factor)

            case resource.EmissiveFactor:
                shader.set_uniform(&lighting_shader, resource.EMISSIVE_FACTOR, v[0], v[1], v[2])

            case resource.EmissiveTexture:
                emissive_texture := resource.get_texture(manager, v)
                bind_texture(texture_unit, emissive_texture.gpu_texture.?)
                shader.set_uniform(&lighting_shader, resource.EMISSIVE_TEXTURE, texture_unit)
                texture_unit += 1

            case resource.OcclusionTexture:
                occlusion_texture := resource.get_texture(manager, v)
                bind_texture(texture_unit, occlusion_texture.gpu_texture.?)
                shader.set_uniform(&lighting_shader, resource.OCCLUSION_TEXTURE, texture_unit)
                texture_unit += 1

            case resource.NormalTexture:
                normal_texture := resource.get_texture(manager, v)
                bind_texture(texture_unit, normal_texture.gpu_texture.?)
                shader.set_uniform(&lighting_shader, resource.NORMAL_TEXTURE, texture_unit)
                texture_unit += 1
        }
    }

    shader.set_uniform(&lighting_shader, resource.MATERIAL_INFOS, transmute(u32)infos)
    return
}


CameraBufferData :: struct #packed {
    position: glm.vec3,
    _pad: float,
    view: glm.mat4,
    projection: glm.mat4
}

update_camera_ubo :: proc(scene: ^ecs.Scene) -> (ok: bool) {
    viewpoint := scene.viewpoint
    if viewpoint == nil {
        dbg.debug_point(dbg.LogLevel.ERROR, "Scene viewpoint is nil!")
        return
    }

    camera_buffer_data := CameraBufferData {
        viewpoint.position,
        camera.camera_look_at(viewpoint),
        camera.get_perspective(viewpoint)
    }

    if RENDER_CONTEXT.camera_ubo == nil {
        RENDER_CONTEXT.camera_ubo = make_shader_buffer(&camera_buffer_data, .UBO, 0, { .WRITE_MANY_READ_MANY, .DRAW })
    }
    else {
        ubo := RENDER_CONTEXT.camera_ubo
        transfer_buffer_data(ubo.id.?, &camera_buffer.data, update=true)
    }
}

update_lights_ssbo :: proc(scene :^ecs.Scene) -> (ok: bool) {
    //todo
    lights_info: ecs.SceneLightSources = scene.light_sources
    LightSSBOData :: struct #packed {
        point_lights: rawptr,
    }
}


// todo full - this is demo
create_lighting_shader :: proc(manager: ^resource.ResourceManager, compile: bool) -> (result: shader.ShaderProgram) {
    shaders: []shader.Shader = {
        shader.read_single_shader_source("../resources/shaders/demo_shader.frag", .FRAGMENT),
        shader.read_single_shader_source("../resources/shaders/demo_shader.vert", .VERTEX),
    }
    result = shader.make_shader_program(shaders)
    transfer_shader(&result)
    return
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
    shader.shader_layout_from_mesh_layout(&vertex, attribute_infos) or_return

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

    // Add shader input/output for both vertex and fragment
    for attribute_info in attribute_infos {
        input_pair := shader.GLSLPair{ shader.glsl_type_from_attribute(attribute_info) or_return, attribute_info.name}
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

    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.BASE_COLOR })  // base colour comes from pbrMetallicRoughness
    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.PBR_METALLIC_ROUGHNESS })
    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.NORMAL_TEXTURE })

    inc_emissive_texture := .EMISSIVE_TEXTURE in material.properties
    inc_occlusion_texture := .OCCLUSION_TEXTURE in material.properties

    if inc_emissive_texture {
        append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.EMISSIVE_TEXTURE })
        append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.vec3, resource.EMISSIVE_FACTOR })
    }

    if inc_occlusion_texture do append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, resource.OCCLUSION_TEXTURE })



    ok = true
    return
}

MODEL_MATRIX_UNIFORM :: "m_Model"
VIEW_MATRIX_UNIFORM :: "m_View"
PROJECTION_MATRIX_UNIFORM :: "m_Projection"
NORMAL_MATRIX_UNIFORM :: "m_Normal"