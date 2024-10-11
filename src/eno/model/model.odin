package model

import "vendor:cgltf"
import "core:testing"
import "core:log"
import "core:slice"

VertexComponent :: struct {
    element_size: uint,
    attr_type: cgltf.attribute_type
}

VertexLayout :: struct {
    sizes : []uint, //Want as u32
    types: []cgltf.attribute_type
}


Mesh :: struct {
    vertices: [dynamic]VertexData,
    layout: ^VertexLayout
}

VertexData :: struct {
    raw_data: [dynamic]f32
}

IndexData :: struct {
    raw_data: [dynamic]u32
}

destroy_mesh :: proc(mesh: ^Mesh) {
    for &vertex in mesh.vertices do delete(vertex.raw_data)
    delete(mesh.vertices)
    free(mesh)
}

destroy_index_data :: proc(index_data: ^IndexData) {
    delete(index_data.raw_data)
    free(index_data)
}

@(test)
destroy_mesh_test :: proc(t: ^testing.T) {
    rawdata: [dynamic]f32
    append(&rawdata, 0.25)

    vert: [dynamic]VertexData
    append(&vert, VertexData{ rawdata })

    vertex_layout := VertexLayout { []uint{3, 3, 4, 2}, []cgltf.attribute_type {
            cgltf.attribute_type.normal,
            cgltf.attribute_type.position,
            cgltf.attribute_type.tangent,
            cgltf.attribute_type.texcoord
    }}

    mesh := new(Mesh)
    mesh.vertices = vert
    mesh.layout = &vertex_layout
    defer destroy_mesh(mesh)
   // log.infof("mesh leak test, check for leaks: %#v", mesh)
}


