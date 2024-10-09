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
    sizes : []uint,
    types: []cgltf.attribute_type
}

/*
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

make_vertex_components_dyna :: proc(offsets: []uint, types: []cgltf.attribute_type) -> (result: [dynamic]VertexComponent) {

    if len(offsets) != len(types) {
        log.errorf("%s: Size of offsets and types are different.", #procedure)
        return result
    }

    result = make([dynamic]VertexComponent, len(offsets))

    for i := 0; i < len(offsets); i += 1 do result[i] = VertexComponent{ offsets[i], types[i] }

    return result
}

deep_clone_components :: proc(components: ^[]VertexComponent) -> (result: []VertexComponent) {
    components_arr := make([dynamic]VertexComponent, len(components))
    defer delete(components_arr)

    log.infof("components before: \n%#v", components)

    for i := 0; i < len(components); i += 1 do components_arr[i] = VertexComponent { components[i].element_size, components[i].attr_type }
    log.infof("components_arr: \n%#v", components_arr)

    return components_arr[:]
}

@(test)
deep_clone_test :: proc(t: ^testing.T) {
    components := make_vertex_components([]uint{3, 3, 4, 2}, []cgltf.attribute_type{
        cgltf.attribute_type.normal,
        cgltf.attribute_type.position,
        cgltf.attribute_type.tangent,
        cgltf.attribute_type.texcoord
    })

    log.infof("components before: \n%#v", components)

    copied_components := deep_clone_components(&components)
    defer delete(copied_components)
   // delete(components)

    log.infof("components: \n%#v", copied_components)
}
*/

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


