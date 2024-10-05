package model

import "vendor:cgltf"
import "core:log"

VertexComponent :: struct {
    offset: uint,
    attr_type: cgltf.attribute_type
}

make_vertex_components :: proc(offsets: []uint, types: []cgltf.attribute_type) -> (result: []VertexComponent) {

    if len(offsets) != len(types) {
        log.errorf("%s: Size of offsets and types are different.", #procedure)
        return result
    }

    result_arr := make([dynamic]VertexComponent, len(offsets))
    defer delete(result_arr)

    for i := 0; i < len(offsets); i += 1 do result_arr[i] = VertexComponent{ offsets[i], types[i] }

    return result_arr[:]
}

Mesh :: struct {
    vertices: [dynamic]VertexData,
    components: [dynamic]VertexComponent
}

VertexData :: struct {
    raw_data: [dynamic]f32
}

