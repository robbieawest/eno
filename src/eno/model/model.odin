package model

import "vendor:cgltf"

VertexComponent :: struct {
    offset: uint,
    attr_type: cgltf.attribute_type
}

Mesh :: struct {
    vertices: []VertexData,
    components: []VertexComponent
}

VertexData :: struct {
    raw_data: []f32
}

