package model

import "core:testing"
import "core:log"
import "vendor:cgltf"

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
    data_type: MeshComponentType,
    byte_stride: u32,  // Describes attribute length in bytes
    float_stride: u32,  // Describes attribute length in number of floats (f32) (byte_stride / 8)
    name: string
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

MeshComponentType :: enum {
    invalid,
    i8,
    u8,
    i16,
    u16,
    u32,
    f32
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
    vertex_data := make([dynamic]f32)
    append(&vertex_data, 0.25)

    mesh: Mesh
    mesh.vertex_data = vertex_data
    defer destroy_mesh(&mesh)
    log.infof("mesh leak test, check for leaks: %#v", mesh)
}


// Textures and materials

MaterialPropertyInfo :: enum {
    SHEEN,
    PBR_METALLIC_ROUGHNESS,
    PBR_METALLIC_GLOSSINESS,
    CLEARCOAT,
    TRANSMISSION,
    VOLUME,
    IOR,
    SPECULAR,
    SHEEN,
    EMISSIVE_STRENGTH,
    IRIDESCENE,
    ANISTROPY,
    DISPERSION,
    DOUBLE_SIDED,
    UNLIT
}

MaterialPropertiesInfos :: bit_set[MaterialPropertyInfo]

Material :: struct {
    properties_info: MaterialPropertiesInfos,
    properties: map[MaterialPropertyInfo]MaterialProperty
}

PbrMetallicRoughness :: cgltf.pbr_metallic_roughness
PbrSpecularGlossiness :: cgltf.pbr_specular_glossiness
Clearcoat :: cgltf.clearcoat
IndexOfRefraction :: cgltf.ior
Specular :: cgltf.specular
Sheen :: cgltf.sheen
Transmission :: cgltf.transmission
Volume :: cgltf.volume
EmissiveStrength :: cgltf.emissive_strength
Iridescence :: cgltf.emissive_strength
Anisotropy :: cgltf.anisotropy
AlphaMode :: cgltf.alpha_mode

MaterialProperty :: union {
    PbrMetallicRoughness,
    PbrSpecularGlossiness,
    Clearcoat,
    IndexOfRefraction,
    Specular,
    Sheen,
    Transmission,
    Volume,
    EmissiveStrength,
    Iridescence,
    Anisotropy,
    AlphaMode
}