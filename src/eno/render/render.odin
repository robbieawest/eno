package render

import "../ecs"
import "../model"
import "../shader"
import "../utils"
import dbg "../debug"

import glm "core:math/linalg/glsl"
import "core:strings"
import "core:fmt"
import "../standards"  // todo fix stupid cyclical import

render :: proc(pipeline: RenderPipeline, scene: ^ecs.Scene) -> (ok: bool) {
    /*
        for later:
            instancing done via InstanceTo ecs component
            batching via combining entities with matching gpu components
    */

    // 1. todo query scene for renderable models
    isVisibleQueryData := true
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = standards.MODEL_COMPONENT.label, include = true },
        { label = standards.VISIBLE_COMPONENT.label, data = &isVisibleQueryData }
    }}
    query_result := ecs.query_scene(scene, query) or_return

    // 2. flatten into lots of meshes
    meshes: [dynamic][]model.Mesh = make([dynamic][]model.Mesh)
    for _, arch_result in query_result {
        for comp_label, comp_ind in arch_result.component_map {
            comp_data := arch_result.data[comp_ind]
            model_data := ecs.components_deserialize(model.Model)  // todo create version which can supply with flat data, and that which gives only the data, no metadata
            append(&meshes, model_data.mesh_data) // like this!
        }
    }

    // 3. get gpu components
    // 4. deal with programs and light/camera uniforms

    //4.

    if len(pipeline.passes) == 0 {
        // Render to default framebuffer directly
        // Make single element draw call per mesh
    }
    else {
        // figure it out when the need is there
    }

    return true
}


LightSourceInformation :: struct {
    enabled: bool,
    intensity: f32,
    colour: glm.vec4
}

PointLight :: struct {
    light_information: LightSourceInformation,
    attenuation: f32
}

DirectionalLight :: struct {
    light_information: LightSourceInformation,
    direction: glm.vec3
}

// Cone shaped light
SpotLight :: struct {
    light_information: LightSourceInformation,
    inner_cone_angle: f32,
    outer_cone_angle: f32,
    attenuation: f32
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
    attribute_infos: model.VertexLayout,
    material: model.Material,
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

    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, model.BASE_COLOR })  // base colour comes from pbrMetallicRoughness
    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, model.PBR_METALLIC_ROUGHNESS })
    append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, model.NORMAL_TEXTURE })

    inc_emissive_texture := .EMISSIVE_TEXTURE in material.properties
    inc_occlusion_texture := .OCCLUSION_TEXTURE in material.properties

    if inc_emissive_texture {
        append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, model.EMISSIVE_TEXTURE })
        append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.vec3, model.EMISSIVE_FACTOR })
    }

    if inc_occlusion_texture do append(&uniforms, shader.GLSLPair{ shader.GLSLDataType.sampler2D, model.OCCLUSION_TEXTURE })



    ok = true
    return
}

MODEL_MATRIX_UNIFORM :: "m_Model"
VIEW_MATRIX_UNIFORM :: "m_View"
PROJECTION_MATRIX_UNIFORM :: "m_Projection"
NORMAL_MATRIX_UNIFORM :: "m_Normal"