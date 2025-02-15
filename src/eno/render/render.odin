package render

import "../ecs"
import "../model"

RenderType :: enum u32 {
    COLOUR = gl.COLOR_BUFFER_BIT,
    DEPTH = gl.DEPTH_BUFFER_BIT,
    STENCIL = gl.STENCIL_BUFFER_BIT
}
RenderMask :: bit_set[RenderType]

ColourMask :: RenderMask{ .COLOUR }
DepthMask :: RenderMask{ .DEPTH }
StencilMask :: RenderMask{ .STENCIL }

/*
    Destroys render pass infos input
*/
forward_render_pipeline :: proc(window_w: i32, window_h: i32, pass_infos: ..PassInfo) -> (pipeline: RenderPipeline, ok: bool) {
    pipeline.passes = make([dynamic]RenderPass, 0, len(pass_info))
    defer destroy_pass_info(pass_infos)

    for pass_info in pass_infos {
        pass: RenderPass
        pass.frame_buffer = generate_framebuffer(window_w, window_h) or_return

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
    }
}


render :: proc(pipeline: RenderPipeline, scene: ^ecs.Scene) {
    // search scene for drawable models (cached?)
    // make it non cached for now


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
