package model

import "vendor:cgltf"

import "core:testing"
import "core:log"
import "core:slice"
import "core:reflect"

/*
VertexLayout :: struct {
    sizes : []u32,
    types: []cgltf.attribute_type
}
*/

VertexLayout :: #soa [dynamic]MeshAttributeInfo

MeshAttributeInfo :: struct {
    type: MeshAttributeType,  // Describes the type of the attribute (position, normal etc)
    element_type: MeshElementType,  // Describes the direct datatype of each element (vec2, vec3 etc)
    byte_stride: u32,  // Describes attribute length in bytes
    float_stride: u32,  // Describes attribute length in number of floats (f32) (byte_stride / 8)
}


MeshElementType :: enum {
    invalid,
    scalar,
    vec2,
    vec3,
    vec4,
    mat2,
    mat3,
    mat4,
}

MeshAttributeType :: enum {
    invalid,
    position,
    normal,
    tangent,
    texcoord,
    color,
    joints,
    weights,
    custom,
}


Mesh :: struct {
    vertex_data: [dynamic]f32,
    layout: VertexLayout
}


IndexData :: struct {
    raw_data: [dynamic]u32
}


destroy_mesh :: proc(mesh: ^Mesh) {
    delete(mesh.vertex_data)
}


destroy_index_data :: proc(index_data: ^IndexData) {
    delete(index_data.raw_data)
}


@(test)
destroy_mesh_test :: proc(t: ^testing.T) {
    vertex_data: [dynamic]f32 = { 0.25 }

    vertex_layout := VertexLayout { []u32{3, 3, 4, 2}, []cgltf.attribute_type {
            cgltf.attribute_type.normal,
            cgltf.attribute_type.position,
            cgltf.attribute_type.tangent,
            cgltf.attribute_type.texcoord
    }}

    mesh: Mesh
    mesh.vertex_data = vertex_data
    mesh.layout = vertex_layout
    defer destroy_mesh(&mesh)
   // log.infof("mesh leak test, check for leaks: %#v", mesh)
}
