package render

import "../model"

import "core:testing"
import "core:log"
import "../shader"

@(test)
forward_lighting_shader_test :: proc(t: ^testing.T) {

    layout := make(#soa[dynamic]model.MeshAttributeInfo, 0); defer delete(layout)
    append_soa_elems(&layout,
        model.MeshAttributeInfo{ .normal, .vec3, .f32, 12, 3, "normal"},
        model.MeshAttributeInfo{ .position, .vec3, .f32, 12, 3, "position"},
        model.MeshAttributeInfo{ .tangent, .vec4, .f32, 16, 4, "tangent"},
        model.MeshAttributeInfo{ .texcoord, .vec2, .f32, 8, 2, "texcoord_0"},  // Not sure how this will be handled...
    )

    material_infos: model.MaterialPropertiesInfos = { .PBR_METALLIC_ROUGHNESS }
    lighting_model := LightingModel.DIRECT
    material_model := MaterialModel.PBR

    vertex, frag, ok := create_forward_lighting_shader(layout, material_infos, lighting_model, material_model)
    testing.expect(t, ok)

    log.infof("Vertex: %#v", vertex)
    log.infof("Frag: %#v", frag)

    shader.destroy_shader_info(vertex)
    shader.destroy_shader_info(frag)
}
