package render

import "../ecs"
import "../model"
import "../shader"
import "../utils"

import glm "core:math/linalg/glsl"
import "core:strings"
import "core:fmt"



/*
    Destroys render pass infos input
*/
forward_render_pipeline :: proc(window_w: i32, window_h: i32, pass_infos: ..PassInfo) -> (pipeline: RenderPipeline, ok: bool) {
    pipeline.passes = make([dynamic]RenderPass, 0, len(pass_infos))
    defer for &pass_info in pass_infos do destroy_pass_info(&pass_info)

    for pass_info in pass_infos {
        pass: RenderPass
        pass.frame_buffer = generate_framebuffer(window_w, window_h) or_return
        /* todo This all needs to be redone - The idea behind pass infos does not really fit until I have figured out the shader process fully
        for attachment_info in pass_info.attachments_info {
            is_render_buffer := attachment_info.buffer_type == .RENDER
            if attachment_info.backing_type == 0 && attachment_info.internal_backing_type == 0 {
                make_attachment(&pass.frame_buffer, attachment_info.type, lod = attachment_info.lod, is_render_buffer = is_render_buffer)
            }
            else if attachment_info.backing_type == 0 {
                make_attachment(&pass.frame_buffer, attachment_info.type, attachment_info.internal_backing_type, lod = attachment_info.lod, is_render_buffer = is_render_buffer)
            }
            else if attachment_info.internal_backing_type == 0 {
                make_attachment(&pass.frame_buffer, attachment_info.type, backing_type = attachment_info.backing_type, lod = attachment_info.lod, is_render_buffer = is_render_buffer)
            }
            else {
                make_attachment(&pass.frame_buffer, attachment_info.type, attachment_info.internal_backing_type, attachment_info.backing_type, attachment_info.lod, is_render_buffer = is_render_buffer)
            }
        }
        */

        append(&pipeline.passes, pass)
    }

    ok = true
    return
}


render :: proc(pipeline: RenderPipeline, scene: ^ecs.Scene) {
    // search scene for drawable models (cached?)
    // make it non cached for now


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
*/
create_forward_lighting_shader :: proc(
    attribute_infos: model.VertexLayout,
    material_infos: model.MaterialPropertiesInfos,
    lighting_model: LightingModel,
    material_model: MaterialModel,
    allocator := context.allocator
) -> (vertex: shader.ShaderInfo, frag: shader.ShaderInfo, ok: bool) {

    // Add input bindings
    shader.shader_layout_from_mesh_layout(&vertex, attribute_infos) or_return

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

    ok = true
    return
}

MODEL_MATRIX_UNIFORM :: "m_Model"
VIEW_MATRIX_UNIFORM :: "m_View"
PROJECTION_MATRIX_UNIFORM :: "m_Projection"
NORMAL_MATRIX_UNIFORM :: "m_Normal"