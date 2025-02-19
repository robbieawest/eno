package render

import "../ecs"
import "../model"

import glm "core:math/linalg/glsl"



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
    attribute_info: model.VertexLayout,
    material: model.Material,
    lighting_model: LightingModel,
    material_model: MaterialModel
) {

}
