package resource

import "vendor:cgltf"
import stbi "vendor:stb/image"

import "../standards"
import dbg "../debug"

import "core:strings"
import glm "core:math/linalg/glsl"
import "core:log"
import utils "../utils"

MODEL_COMPONENT := standards.ComponentTemplate{ "Model", Model, size_of(Model) }

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
    vertices_count: int,
    index_data: IndexData,
    indices_count: int,
    layout: VertexLayout,
    material: Maybe(MaterialID),
    gl_component: GLComponent
}

GLComponent :: struct {
    vao: VertexArrayObject,
    vbo: VertexBufferObject,
    ebo: ElementBufferObject
}

VertexArrayObject :: Maybe(u32)
VertexBufferObject :: Maybe(u32)
ElementBufferObject :: Maybe(u32)

// DOES NOT RELEASE GPU MEMORY - USE RENDERER PROCEDURES FOR THIS
destroy_mesh :: proc(mesh: ^Mesh) {
    delete(mesh.vertex_data)
    delete(mesh.index_data)
}


// Textures and materials
// base colour, pbr metallic, normal, occlusion and emissive texure/factor are supported currently
MATERIAL_INFOS :: "materialInfos"

PBR_METALLIC_ROUGHNESS :: "pbrMetallicRoughness"
METALLIC_FACTOR :: "metallicFactor"
ROUGHNESS_FACTOR :: "roughnessFactor"
BASE_COLOUR_TEXTURE :: "baseColourTexture"
BASE_COLOUR_FACTOR :: "baseColourFactor"

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
    ALPHA_MODE0,
    ALPHA_CUTOFF
}
MaterialPropertiesInfos :: bit_set[MaterialPropertyInfo; u32]

MaterialID :: u32
Material :: struct {
    name: string,
    properties: map[MaterialPropertyInfo]MaterialProperty,
    double_sided: bool,
    unlit: bool,
    lighting_shader: Maybe(ShaderID)
}

PBRMetallicRoughness :: struct {
    base_colour: TextureID,
    metallic_roughness: TextureID,
    base_colour_factor: [4]f32,
    metallic_factor: f32,
    roughness_factor: f32
}

NormalTexture :: distinct TextureID
OcclusionTexture :: distinct TextureID
EmissiveTexture :: distinct TextureID
EmissiveFactor :: distinct [3]f32

/*
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

AlphaMode :: cgltf.alpha_mode
AlphaCutoff :: f32
*/



MaterialProperty :: struct {
    tag: string,
    value: union {
        PBRMetallicRoughness,
        NormalTexture,
        OcclusionTexture,
        EmissiveTexture,
        EmissiveFactor
    }
}

// Assumes the resource manager is properly initialized
eno_material_from_cgltf_material :: proc(manager: ^ResourceManager, cmat: cgltf.material, gltf_file_location: string) -> (material: Material, ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Converting cgltf material: %s", cmat.name)
    if cmat.name != nil do material.name = strings.clone_from_cstring(cmat.name)

    if cmat.has_pbr_metallic_roughness {
        base_tex := texture_from_cgltf_texture(cmat.pbr_metallic_roughness.base_color_texture.texture, gltf_file_location) or_return
        log.infof("base tex: %#v", base_tex)
        met_rough_tex := texture_from_cgltf_texture(cmat.pbr_metallic_roughness.metallic_roughness_texture.texture, gltf_file_location) or_return

        base_tex_id := add_texture_to_manager(manager, base_tex)
        met_rough_id := add_texture_to_manager(manager, met_rough_tex)

        metallic_roughness := PBRMetallicRoughness {
            base_tex_id,
            met_rough_id,
            cmat.pbr_metallic_roughness.base_color_factor,
            cmat.pbr_metallic_roughness.metallic_factor,
            cmat.pbr_metallic_roughness.roughness_factor
        }
        material.properties[.PBR_METALLIC_ROUGHNESS] = { PBR_METALLIC_ROUGHNESS, metallic_roughness }
    }

    if cmat.normal_texture.texture != nil {
        tex := texture_from_cgltf_texture(cmat.normal_texture.texture, gltf_file_location) or_return
        tex_id := add_texture_to_manager(manager, tex)
        material.properties[.NORMAL_TEXTURE] = { NORMAL_TEXTURE, NormalTexture(tex_id) }
    }
    if cmat.occlusion_texture.texture != nil {
        tex := texture_from_cgltf_texture(cmat.occlusion_texture.texture, gltf_file_location) or_return
        tex_id := add_texture_to_manager(manager, tex)
        material.properties[.OCCLUSION_TEXTURE] = { OCCLUSION_TEXTURE, OcclusionTexture(tex_id) }
    }
    if cmat.emissive_texture.texture != nil {
        tex := texture_from_cgltf_texture(cmat.emissive_texture.texture, gltf_file_location) or_return
        tex_id := add_texture_to_manager(manager, tex)
        material.properties[.EMISSIVE_TEXTURE] = { EMISSIVE_TEXTURE, EmissiveTexture(tex_id) }
        material.properties[.EMISSIVE_FACTOR] = { EMISSIVE_FACTOR, EmissiveFactor(cmat.emissive_factor) }
    }

    material.double_sided = bool(cmat.double_sided)
    material.unlit = bool(cmat.unlit)

    ok = true
    return
}

Model :: struct {
    name: string,
    meshes: [dynamic]Mesh,
}

TextureID :: u32
Texture :: struct {
    name: string,
    image: Image,
    gpu_texture: Maybe(u32)
}

Image :: struct {
    name: string,
    w, h, channels: i32,
    pixel_data: rawptr,  // Can be nil for no data
}

texture_from_cgltf_texture :: proc(texture: ^cgltf.texture, gltf_file_location: string) -> (result: Texture, ok: bool) {
    log.infof("cgltf texture: %#v", texture)
    return Texture {
        strings.clone_from_cstring(texture.name),
        load_image_from_cgltf_image(texture.image_, gltf_file_location) or_return,
        nil
    }, true
}

load_image_from_cgltf_image :: proc(image: ^cgltf.image, gltf_file_location: string) -> (result: Image, ok: bool) {
    log.infof("cgltf image: %#v", image)
    if image.name != nil do result.name = strings.clone_from_cstring(image.name)
    dbg.debug_point(dbg.LogLevel.INFO, "Reading cgltf image: %s", image.uri)

    if image.buffer_view == nil {
        if image.uri == nil {
            dbg.debug_point(dbg.LogLevel.ERROR, "CGLTF image does not have any data attached, URI or buffer data")
            return
        }

        // Use URI
        path := utils.concat(gltf_file_location, string(image.uri)); defer delete(path)
        path_cstr := strings.clone_to_cstring(path); defer delete(path_cstr)
        result.pixel_data = stbi.load(path_cstr, &result.w, &result.h, &result.channels, 0)
        if result.pixel_data == nil {
            dbg.debug_point(dbg.LogLevel.ERROR, "Could not read pixel data from file: %s", image.uri)
            return
        }
        log.infof("result after load: %#v:", result)
    }
    else {
        // Use buffer
        image_buffer: [^]byte = transmute([^]byte)(uintptr(image.buffer_view.buffer.data) + uintptr(image.buffer_view.offset))
        result.pixel_data = stbi.load_from_memory(image_buffer, i32(image.buffer_view.size), &result.w, &result.h, &result.channels, 0)
        if result.pixel_data == nil {
            dbg.debug_point(dbg.LogLevel.ERROR, "Could not read pixel data from memory")
            return
        }
    }


    ok = true
    return
}

LightSourceInformation :: struct {
    name: string,
    enabled: bool,
    intensity: f32,
    colour: glm.vec4,
    position: glm.vec3
}

PointLight :: LightSourceInformation
DirectionalLight :: struct {
    light_information: LightSourceInformation,
    direction: glm.vec3
}

// Cone shaped light
SpotLight :: struct {
    light_information: LightSourceInformation,
    direction: glm.vec3,
    inner_cone_angle: f32,
    outer_cone_angle: f32,
}

POINT_LIGHT_COMPONENT := standards.ComponentTemplate{ "PointLight", PointLight, size_of(PointLight) }
DIRECTIONAL_LIGHT_COMPONENT := standards.ComponentTemplate{ "DirectionalLight", DirectionalLight, size_of(DirectionalLight) }
SPOT_LIGHT_COMPONENT := standards.ComponentTemplate{ "SpotLight", SpotLight, size_of(SpotLight) }
