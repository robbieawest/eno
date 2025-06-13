package model

import "vendor:cgltf"

import "core:strings"

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


VertexData :: [dynamic]f32
IndexData :: [dynamic]u32

Mesh :: struct {
    vertex_data: VertexData,
    index_data: IndexData,
    layout: VertexLayout,
    material: Material,
    gl_component: GLComponent
}

GLComponent :: struct {
    vao: VertexArrayObject,
    vbo: VertexBufferObject,
    ebo: ElementBufferObject
}

VertexArrayObject :: struct {
    id: u32,
    transferred: bool
}

VertexBufferObject :: struct {
    id: u32,
    transferred: bool
}

ElementBufferObject :: struct {
    id: u32,
    transferred: bool
}

// DOES NOT RELEASE GPU MEMORY - USE RENDERER PROCEDURES FOR THIS
destroy_mesh :: proc(mesh: ^Mesh) {
    delete(mesh.vertex_data)
    delete(mesh.index_data)
}


// Textures and materials
// base colour, pbr metallic, normal, occlusion and emissive texure/factor are supported currently

BASE_COLOR :: "albedo"
PBR_METALLIC_ROUGHNESS :: "pbrMetallicRoughness"
PBR_SPECULAR_GLOSSINESS :: "pbrSpecularGlossiness"
CLEARCOAT :: "clearcoat"
TRANSMISSION :: "transmission"
VOLUME :: "volume"
INDEX_OF_REFRACTION :: "ior"
SPECULAR :: "specular"
SHEEN :: "sheen"
EMISSIVE_STRENGTH :: "emissiveStrength"
IRIDESCENCE :: "iridescence"
ANISTROPY:: "anistropy"
DISPERSION :: "dispersion"
NORMAL_TEXTURE :: "normalTexture"
OCCLUSION_TEXTURE :: "occlusionTexture"
EMISSIVE_TEXTURE:: "emissiveTexture"
EMISSIVE_FACTOR :: "emissiveFactor"
ALPHA_MODE :: "alphaMode"
ALPHA_CUTOFF :: "alphaCutoff"
DOUBLE_SIDED:: "doubleSided"
UNLIT :: "unlit"

MaterialPropertyInfo :: enum {
    PBR_METALLIC_ROUGHNESS,
    PBR_SPECULAR_GLOSSINESS,
    CLEARCOAT,
    TRANSMISSION,
    VOLUME,
    INDEX_OF_REFRACTION,
    SPECULAR,
    SHEEN,
    EMISSIVE_STRENGTH,
    IRIDESCENCE,
    ANISTROPY,
    DISPERSION,
    NORMAL_TEXTURE,
    OCCLUSION_TEXTURE,
    EMISSIVE_TEXTURE,
    EMISSIVE_FACTOR,
    ALPHA_MODE,
    ALPHA_CUTOFF
}

MaterialPropertiesInfos :: bit_set[MaterialPropertyInfo]

Material :: struct {
    name: string,
    properties: map[MaterialPropertyInfo]MaterialProperty,
    double_sided: bool,  // Not supported in lighting yet
    unlit: bool  // Not supported in lighting yet
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
Iridescence :: cgltf.iridescence
Anisotropy :: cgltf.anisotropy
Dispersion :: cgltf.dispersion
NormalTexture :: distinct cgltf.texture_view
OcclusionTexture :: distinct cgltf.texture_view
EmissiveTexture :: distinct cgltf.texture_view
EmissiveFactor :: [3]f32
AlphaMode :: cgltf.alpha_mode
AlphaCutoff :: f32


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
    Dispersion,
    NormalTexture,
    OcclusionTexture,
    EmissiveTexture,
    EmissiveFactor,
    AlphaMode,
    AlphaCutoff
}


eno_material_from_cgltf_material :: proc(cmat: cgltf.material) -> (material: Material) {
    material.name = strings.clone_from_cstring(cmat.name)

    if cmat.has_pbr_metallic_roughness do material.properties[.PBR_METALLIC_ROUGHNESS] = cmat.pbr_metallic_roughness
    if cmat.has_pbr_specular_glossiness do material.properties[.PBR_SPECULAR_GLOSSINESS] = cmat.pbr_specular_glossiness
    if cmat.has_clearcoat do material.properties[.CLEARCOAT] = cmat.clearcoat
    if cmat.has_transmission do material.properties[.TRANSMISSION] = cmat.transmission
    if cmat.has_volume do material.properties[.VOLUME] = cmat.volume
    if cmat.has_ior do material.properties[.INDEX_OF_REFRACTION] = cmat.ior
    if cmat.has_specular do material.properties[.SPECULAR] = cmat.specular
    if cmat.has_sheen do material.properties[.SHEEN] = cmat.sheen
    if cmat.has_emissive_strength do material.properties[.EMISSIVE_STRENGTH] = cmat.emissive_strength
    if cmat.has_iridescence do material.properties[.IRIDESCENCE] = cmat.iridescence
    if cmat.has_anisotropy do material.properties[.ANISTROPY] = cmat.anisotropy
    if cmat.has_dispersion do material.properties[.DISPERSION] = cmat.dispersion

    material.double_sided = bool(cmat.double_sided)
    material.unlit = bool(cmat.unlit)

    if cmat.normal_texture.texture != nil do material.properties[.NORMAL_TEXTURE] = NormalTexture(cmat.normal_texture)
    if cmat.occlusion_texture.texture != nil do material.properties[.OCCLUSION_TEXTURE] = OcclusionTexture(cmat.occlusion_texture)
    if cmat.emissive_texture.texture != nil {
        material.properties[.EMISSIVE_TEXTURE] = EmissiveTexture(cmat.emissive_texture)
        material.properties[.EMISSIVE_FACTOR] = cmat.emissive_factor
    }

    return
}


Model :: struct {
    meshes: [dynamic]Mesh,
}