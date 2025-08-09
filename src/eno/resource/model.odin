package resource

import "vendor:cgltf"
import stbi "vendor:stb/image"

import "../standards"
import dbg "../debug"
import "../utils"

import "base:runtime"
import "core:mem"
import "core:strings"
import glm "core:math/linalg/glsl"
import "core:log"
import file_utils "../file_utils"

MODEL_COMPONENT := standards.ComponentTemplate{ "Model", Model, size_of(Model) }
LIGHT_COMPONENT := standards.ComponentTemplate{ "Light", Light, size_of(Light) }


// Although used in the INSTANCE_TO_COMPONENT, it is also a field in Mesh
InstanceTo :: struct {
    // array of world components?
}

/*
    This component is used to instance an entire entity's model data
    It requres a MODEL_COMPONENT to be available in the entity
    Making this a component instead of a field in Model seems apt although I'm not sure why
*/
INSTANCE_TO_COMPONENT := standards.ComponentTemplate{ "InstanceTo",  InstanceTo, size_of(InstanceTo) }


/*
VertexLayout :: struct {
    sizes : []u32,
    types: []cgltf.attribute_type
}
*/

VertexLayout :: struct {
    infos: []MeshAttributeInfo,
    // Decides if the VertexLayout should be grouped with duplicates in the resource manager or not
    // Use when the vertex shader should be unique to layouts with the same mesh attribute infos
    unique: bool,
    shader: ResourceID
}

destroy_vertex_layout :: proc(manager: ^ResourceManager, layout: VertexLayout) -> (ok: bool) {
    for attr_info in layout.infos do delete(attr_info.name)
    delete(layout.infos)

    remove_shader(manager, layout.shader) or_return
    return true
}


MeshAttributeInfo :: struct {
    type: MeshAttributeType,  // Describes the type of the attribute (position, normal etc)
    element_type: MeshElementType,  // Describes the direct datatype of each element (vec2, vec3 etc)
    data_type: MeshComponentType,
    byte_stride: u32,  // Describes attribute length in bytes
    float_stride: u32,  // Describes attribute length in number of floats (f32) (byte_stride / 4)
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

MeshID :: Maybe(MeshIdent)
MeshIdent :: u32
Mesh :: struct {
    vertex_data: VertexData,
    vertices_count: int,
    index_data: IndexData,
    indices_count: int,
    layout: ResourceIdent,
    material: Material,
    mesh_id: MeshID,  // Used in render.RenderPassStore to find the shaders for each render pass
    gl_component: GLComponent,
    is_billboard: bool,  // todo remove
    instance_to: Maybe(InstanceTo)  // Todo support EXT_mesh_gpu_instancing gltf extension for this
}

// Regrettable to have this in resource
GLComponent :: struct {  // If I ever move to glMultiDrawElementsIndirect and grouping VAOs by vertex attribute permutations then this will change
    vao: VertexArrayObject,
    vbo: VertexBufferObject,
    ebo: ElementBufferObject
}

VertexArrayObject :: Maybe(u32)
VertexBufferObject :: Maybe(u32)
ElementBufferObject :: Maybe(u32)

// DOES NOT RELEASE GPU MEMORY - USE RENDERER PROCEDURES FOR THIS
destroy_mesh :: proc(manager: ^ResourceManager, mesh: ^Mesh) -> (ok: bool) {
    delete(mesh.vertex_data)
    delete(mesh.index_data)
    remove_layout(manager, mesh.layout) or_return
    return true
}

// Does not transfer
texture_from_path :: proc(manager: ^ResourceManager, name: string, path: string, path_base: string = "", flip_image := false) -> (id: ResourceIdent, ok: bool) {
    texture: Texture
    texture.image = load_image_from_uri(path, path_base, flip_image) or_return
    texture.name = strings.clone(name)
    return add_texture(manager, texture)
}

// Does not transfer
create_billboard_model_from_path :: proc(manager: ^ResourceManager, texture_name: string, texture_path: string, texture_path_base: string = "") -> (model: Model, ok: bool) {
    texture_id := texture_from_path(manager, texture_name, texture_path, texture_path_base, flip_image = true) or_return
    return create_billboard_model_from_id(manager, texture_id)
}

// Does not transfer
// Todo use unlit property
// todo use special vertex shader
create_billboard_model_from_id :: proc(manager: ^ResourceManager, id: ResourceIdent, allocator := context.allocator) -> (model: Model, ok: bool) {
    texture, tex_ok := get_texture(manager, id); if !tex_ok {
        dbg.log(.ERROR, "Texture does not map to an existing texture in the manager")
        return
    }

    model.meshes = make([dynamic]Mesh, 1)

    billboard_mesh := primitive_square_mesh_data(manager, true, allocator)
    billboard_mesh.is_billboard = true

    material: Material
    material.properties = make(map[MaterialPropertyInfo]MaterialProperty)
    material.properties[.BASE_COLOUR_TEXTURE] = { BASE_COLOUR_TEXTURE, BaseColourTexture(id) }

    material_type: MaterialType
    material_type.unlit = true
    material_type.double_sided = true
    material_type.properties = { .BASE_COLOUR_TEXTURE }
    // material_type.lighting_shader = get_billboard_lighting_shader(manager) or_return
    // ^ needs to change with new shader management

    id := add_material(manager, material_type) or_return
    material.type = id
    billboard_mesh.material = material
    model.meshes[0] = billboard_mesh

    ok = true
    return
}

// Primitive meshes

// Does not give a material
primitive_square_mesh_data :: proc(manager: ^ResourceManager, unique_layout: bool, allocator := context.allocator) -> (mesh: Mesh) {
    mesh.vertex_data = make(VertexData, allocator=allocator)
    mesh.index_data = make(IndexData, allocator=allocator)
    append_elems(&mesh.vertex_data,
        -1, 1, 0,  0.0, 1.0,
        1, 1, 0,  1.0, 1.0,
        -1, -1, 0,  0.0, 0.0,
        1, -1, 0,  1.0, 0.0
    )
    append_elems(&mesh.index_data,
        0, 1, 2,
        2, 1, 3
    )
    mesh.vertices_count = len(mesh.vertex_data)
    mesh.indices_count = len(mesh.index_data)

    layout: VertexLayout
    layout.infos = make([]MeshAttributeInfo, 2, allocator=allocator)
    layout.infos[0] = { .position, .vec3, .f32, 12, 3, strings.clone("aPosition")}
    layout.infos[1] = { .texcoord, .vec2, .f32, 8, 2, strings.clone("aTexCoords")}
    layout.unique = unique_layout
    add_vertex_layout(manager, layout)

    return
}

//


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
    BASE_COLOUR_TEXTURE,
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
MaterialPropertyInfos :: bit_set[MaterialPropertyInfo; u32]

Material :: struct {
    name: string,
    type: ResourceIdent,
    properties: map[MaterialPropertyInfo]MaterialProperty
}

MaterialType :: struct {
    properties: MaterialPropertyInfos,
    double_sided: bool,
    unlit: bool,
    // unique field specifies that it should not be grouped with duplicate MaterialType's in the manager
    // Use when the lighting shader is special and must differ from these duplicate permutations
    unique: bool,
    shader: ResourceID,
}


destroy_material :: proc(manager: ^ResourceManager, material: Material, allocator := context.allocator) -> (ok: bool) {
    ok = true
    delete(material.name, allocator)
    for _, property in material.properties {
        // delete(property.tag, allocator) tag expected to be literal

        #partial switch v in property.value {
            case PBRMetallicRoughness:
                ok &= remove_texture(manager, v.metallic_roughness)
                ok &= remove_texture(manager, v.base_colour)
            case EmissiveTexture:
                ok &= remove_texture(manager, ResourceIdent(v))
            case OcclusionTexture:
                ok &= remove_texture(manager, ResourceIdent(v))
            case NormalTexture:
                ok &= remove_texture(manager, ResourceIdent(v))
            case BaseColourTexture:
                ok &= remove_texture(manager, ResourceIdent(v))
        }
    }

    remove_material(manager, material.type) or_return  // Will delete lighting shader
    return true
}

destroy_material_type :: proc(manager: ^ResourceManager, type: MaterialType) -> (ok: bool) {
    if type.shader != nil do remove_shader(manager, type.shader) or_return
    return true
}


PBRMetallicRoughness :: struct {
    base_colour: ResourceIdent,
    metallic_roughness: ResourceIdent,
    base_colour_factor: [4]f32,
    metallic_factor: f32,
    roughness_factor: f32
}

BaseColourTexture :: distinct ResourceIdent
NormalTexture :: distinct ResourceIdent
OcclusionTexture :: distinct ResourceIdent
EmissiveTexture :: distinct ResourceIdent
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
        BaseColourTexture,
        PBRMetallicRoughness,
        NormalTexture,
        OcclusionTexture,
        EmissiveTexture,
        EmissiveFactor
    }
}

// Assumes the resource manager is properly initialized
eno_material_from_cgltf_material :: proc(manager: ^ResourceManager, cmat: cgltf.material, gltf_file_location: string) -> (material: Material, ok: bool) {
    dbg.log(.INFO, "Converting cgltf material: %s", cmat.name)
    if cmat.name != nil do material.name = strings.clone_from_cstring(cmat.name)

    material_type: MaterialType

    if cmat.has_pbr_metallic_roughness {
        material_type.properties |= { .PBR_METALLIC_ROUGHNESS }

        base_tex := texture_from_cgltf_texture(cmat.pbr_metallic_roughness.base_color_texture.texture, gltf_file_location) or_return
        met_rough_tex := texture_from_cgltf_texture(cmat.pbr_metallic_roughness.metallic_roughness_texture.texture, gltf_file_location) or_return

        base_tex_id := add_texture(manager, base_tex) or_return
        met_rough_id := add_texture(manager, met_rough_tex) or_return

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
        material_type.properties |= { .NORMAL_TEXTURE }

        tex := texture_from_cgltf_texture(cmat.normal_texture.texture, gltf_file_location) or_return
        tex_id := add_texture(manager, tex) or_return
        material.properties[.NORMAL_TEXTURE] = { NORMAL_TEXTURE, NormalTexture(tex_id) }
    }
    if cmat.occlusion_texture.texture != nil {
        material_type.properties |= { .OCCLUSION_TEXTURE }

        tex := texture_from_cgltf_texture(cmat.occlusion_texture.texture, gltf_file_location) or_return
        tex_id := add_texture(manager, tex) or_return
        material.properties[.OCCLUSION_TEXTURE] = { OCCLUSION_TEXTURE, OcclusionTexture(tex_id) }
    }
    if cmat.emissive_texture.texture != nil {
        material_type.properties |= { .EMISSIVE_TEXTURE, .EMISSIVE_FACTOR}

        tex := texture_from_cgltf_texture(cmat.emissive_texture.texture, gltf_file_location) or_return
        tex_id := add_texture(manager, tex) or_return
        material.properties[.EMISSIVE_TEXTURE] = { EMISSIVE_TEXTURE, EmissiveTexture(tex_id) }
        material.properties[.EMISSIVE_FACTOR] = { EMISSIVE_FACTOR, EmissiveFactor(cmat.emissive_factor) }
    }

    material_type.double_sided = bool(cmat.double_sided)
    material_type.unlit = bool(cmat.unlit)

    type_id := add_material(manager, material_type) or_return
    material.type = type_id

    ok = true
    return
}

Model :: struct {
    name: string,
    meshes: [dynamic]Mesh,
}


TextureType :: enum {
    TWO_DIM,
    THREE_DIM,
    CUBEMAP
}

TextureProperty :: enum {
    WRAP_S,
    WRAP_T,
    WRAP_R,
    MIN_FILTER,
    MAG_FILTER
}

TexturePropertyValue :: enum {
    CLAMP_EDGE,
    CLAMP_BORDER,
    REPEAT,
    MIRROR_CLAMP_EDGE,
    MIRROR_REPEAT,
    NEAREST,
    LINEAR,
    LINEAR_MIPMAP_LINEAR,
    LINEAR_MIPMAP_NEAREST,
    NEAREST_MIPMAP_LINEAR,
    NEAREST_MIPMAP_NEAREST
}

TextureProperties :: map[TextureProperty]TexturePropertyValue

default_texture_properties :: proc(allocator := context.allocator) -> (properties: TextureProperties) {
    properties = make(TextureProperties, allocator=allocator)
    properties[.WRAP_S] = .CLAMP_EDGE
    properties[.WRAP_T] = .CLAMP_EDGE
    properties[.WRAP_R] = .CLAMP_EDGE
    properties[.MIN_FILTER] = .LINEAR
    properties[.MAG_FILTER] = .LINEAR
    return
}

Texture :: struct {
    name: string,
    image: Image,  // For a cubemap this would be the raw environment map to convert to cubemap. gpu_texture will always != nil when not needed
    gpu_texture: Maybe(u32),
    type: TextureType,
    properties: TextureProperties
}

// Does not release GPU memory
destroy_texture :: proc(texture: ^Texture) {
    delete(texture.name)
    destroy_image(&texture.image)
}

Image :: struct {
    name: string,
    w, h, channels: i32,
    pixel_data: rawptr  // Can be nil for no data
}

destroy_image :: proc(image: ^Image) {
    delete(image.name)
    destroy_pixel_data(image)
}

destroy_pixel_data :: proc(image: ^Image) {
    if image.pixel_data != nil do stbi.image_free(image.pixel_data)
    image.pixel_data = nil
}

texture_from_cgltf_texture :: proc(texture: ^cgltf.texture, gltf_file_location: string, allocator := context.allocator, loc := #caller_location) -> (result: Texture, ok: bool) {
    if texture == nil do return result, true
    return Texture {
        name = strings.clone_from_cstring(texture.name),
        image = load_image_from_cgltf_image(texture.image_, gltf_file_location, allocator=allocator, loc=loc) or_return
    }, true
}

load_image_from_cgltf_image :: proc(image: ^cgltf.image, gltf_file_location: string, allocator := context.allocator, loc := #caller_location) -> (result: Image, ok: bool) {
    if image.name != nil do result.name = strings.clone_from_cstring(image.name, allocator=allocator)
    dbg.log(.INFO, "Reading cgltf image: %s", image.uri)

    if image.buffer_view == nil {
        if image.uri == nil {
            dbg.log(.ERROR, "CGLTF image does not have any data attached, URI or buffer data")
            return
        }

        // Use URI
        return load_image_from_uri(string(image.uri), gltf_file_location, allocator=allocator, loc=loc)
    }

    // Use buffer
    // todo not tested, mimeType MUST be used via spec
    image_buffer: [^]byte = transmute([^]byte)(uintptr(image.buffer_view.buffer.data) + uintptr(image.buffer_view.offset))
    result.pixel_data = stbi.load_from_memory(image_buffer, i32(image.buffer_view.size), &result.w, &result.h, &result.channels, 0)

    if result.pixel_data == nil {
        dbg.log(.ERROR, "Could not read pixel data from memory")
        return
    }

    ok = true
    return
}


load_image_from_uri :: proc(uri: string, uri_base: string = "", flip_image := false, desired_channels := 4, as_float := false, allocator := context.allocator, loc := #caller_location) -> (result: Image, ok: bool) {

    path := len(uri_base) == 0 ? strings.clone(uri, allocator=allocator) : utils.concat(uri_base, uri, allocator=allocator); defer delete(path)
    file_utils.check_path(path, loc=loc) or_return
    path_cstr := strings.clone_to_cstring(path, allocator=allocator); defer delete(path_cstr)

    if flip_image do stbi.set_flip_vertically_on_load(1)
    defer if flip_image do stbi.set_flip_vertically_on_load(0)

    if as_float do result.pixel_data = stbi.loadf(path_cstr, &result.w, &result.h, &result.channels, 4)
    else do result.pixel_data = stbi.load(path_cstr, &result.w, &result.h, &result.channels, 4)
    if result.pixel_data == nil {
        dbg.log(.ERROR, "Could not read pixel data from file: %s", uri)
        return
    }

    ok = true
    return
}


LightSourceInformation :: struct {
    name: string,
    enabled: bool,
    intensity: f32,
    colour: glm.vec3,
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

Light :: union {
    SpotLight,
    DirectionalLight,
    PointLight
}

make_light_billboard :: proc(manager: ^ResourceManager) -> (model: Model, ok: bool) {
    if manager.billboard_id == nil {
        manager.billboard_id = texture_from_path(manager, "light_billboard", "light.png", standards.TEXTURE_RESOURCE_PATH, flip_image = true) or_return
        if manager.billboard_id == nil {
            dbg.log(.ERROR, "texture_from_path returned nil id")
            return
        }
    }
    return create_billboard_model_from_id(manager, manager.billboard_id.?)
}


POINT_LIGHT_COMPONENT := standards.ComponentTemplate{ "PointLight", PointLight, size_of(PointLight) }
DIRECTIONAL_LIGHT_COMPONENT := standards.ComponentTemplate{ "DirectionalLight", DirectionalLight, size_of(DirectionalLight) }
SPOT_LIGHT_COMPONENT := standards.ComponentTemplate{ "SpotLight", SpotLight, size_of(SpotLight) }
