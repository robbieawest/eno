package cyclic_tests

import "vendor:cgltf"
import "core:testing"
import "core:log"
import "../model"
import "../utils"

@(test)
copy_slice_to_dynamic_test :: proc(t: ^testing.T) {
    slice_inp := model.make_vertex_components([]uint{3, 3}, []cgltf.attribute_type{cgltf.attribute_type.normal, cgltf.attribute_type.position})
    dyna := make([dynamic]model.VertexComponent, 0)
    defer delete(dyna)

    utils.copy_slice_to_dynamic(&dyna, slice_inp)

    log.infof("dyna: \n%#v", dyna)
    testing.expect_value(t, len(dyna), len(slice_inp))
    for i := 0; i < len(dyna); i += 1 do testing.expect_value(t, dyna[i], slice_inp[i])
}
