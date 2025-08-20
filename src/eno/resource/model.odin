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
import "core:math/linalg"

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
    instance_to: Maybe(InstanceTo),  // Todo support EXT_mesh_gpu_instancing gltf extension for this
    centroid: [3]f32,  // Local centroid, used in occlusion/frustum culling (if I do them) and in z-sorting. Applied hierarchically via model world component
    transpose_transformation: bool
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
texture_from_path :: proc(
    manager: ^ResourceManager,
    name: string,
    path: string,
    path_base: string = "",
    flip_image := false,
    type: TextureType = .TWO_DIM,
    properties: TextureProperties = {},
    allocator := context.allocator
) -> (id: ResourceIdent, ok: bool) {
    texture: Texture
    texture.image = load_image_from_uri(path, path_base, flip_image, allocator=allocator) or_return
    texture.name = strings.clone(name, allocator=allocator)

    if len(properties) == 0 do texture.properties = default_texture_properties(allocator)
    else do texture.properties = properties
    texture.type = type
    return add_texture(manager, texture)
}



// Primitive meshes

// Does not give a material
primitive_square_mesh_data :: proc(allocator := context.allocator) -> (mesh: Mesh) {
    mesh.vertex_data = make(VertexData, allocator=allocator)
    mesh.index_data = make(IndexData, allocator=allocator)
    append_elems(&mesh.vertex_data,
        -1, 1, 0,  0.0, 1.0,
        1, 1, 0,  1.0, 1.0,
        -1, -1, 0,  0.0, 0.0,
        1, -1, 0,  1.0, 0.0
    )
    append_elems(&mesh.index_data,
        2, 1, 0,
        3, 1, 2
    )
    mesh.vertices_count = len(mesh.vertex_data)
    mesh.indices_count = len(mesh.index_data)

    return
}

primitive_square_mesh_layout :: proc(unique_layout: bool, allocator := context.allocator) -> (layout: VertexLayout) {
    layout.infos = make([]MeshAttributeInfo, 2, allocator=allocator)
    layout.infos[0] = { .position, .vec3, .f32, 12, 3, strings.clone("aPosition")}
    layout.infos[1] = { .texcoord, .vec2, .f32, 8, 2, strings.clone("aTexCoords")}
    layout.unique = unique_layout
    return
}

//


// Textures and materials
// I expect this could be done better with an enumerated array on MaterialPropertyInfo
MATERIAL_USAGES :: "materialUsages"

PBR_METALLIC_ROUGHNESS :: "pbrMetallicRoughness"
// For specifying shader uniforms:
METALLIC_FACTOR :: "metallicFactor"
ROUGHNESS_FACTOR :: "roughnessFactor"
BASE_COLOUR_TEXTURE :: "baseColourTexture"
BASE_COLOUR_FACTOR :: "baseColourFactor"
BASE_COLOUR_OVERRIDE :: "baseColourOverride"
ENABLE_BASE_COLOUR_OVERRIDE :: "enableBaseColourOverride"

CLEARCOAT :: "clearcoat"
// For specifying shader uniforms:
CLEARCOAT_TEXTURE :: "clearcoatTexture"
CLEARCOAT_ROUGHNESS_TEXTURE :: "clearcoatRoughnessTexture"
CLEARCOAT_NORMAL_TEXTURE :: "clearcoatNormalTexture"
CLEARCOAT_FACTOR :: "clearcoatFactor"
CLEARCOAT_ROUGHNESS_FACTOR :: "clearcoatRoughnessFactor"

PBR_SPECULAR_GLOSSINESS :: "pbrSpecularGlossiness"
TRANSMISSION :: "transmission"
VOLUME :: "volume"
INDEX_OF_REFRACTION :: "ior"

SPECULAR :: "specular"
SPECULAR_TEXTURE :: "specularTexture"
SPECULAR_COLOUR_TEXTURE :: "specularColourTexture"
SPECULAR_FACTOR :: "specularFactor"
SPECULAR_COLOUR_FACTOR :: "specularColourFactor"

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
ENABLE_ALPHA_CUTOFF :: "enableAlphaCutoff"

DOUBLE_SIDED :: "doubleSided"
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
}

MaterialPropertyInfos :: bit_set[MaterialPropertyInfo]
Material :: struct {
    name: string,
    type: ResourceIdent,
    alpha_cutoff: f32,
    emissive_factor: [3]f32,
    properties: map[MaterialPropertyInfo]MaterialProperty
}


MaterialType :: struct {
    properties: MaterialPropertyInfos,
    double_sided: bool,
    alpha_mode: AlphaMode,
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
        }
    }

    remove_material(manager, material.type) or_return  // Will delete lighting shader
    return true
}

destroy_material_type :: proc(manager: ^ResourceManager, type: MaterialType) -> (ok: bool) {
    if type.shader != nil do remove_shader(manager, type.shader) or_return
    return true
}

AlphaMode :: enum {
    OPAQUE,
    MASK,
    BLEND
}

PBRMetallicRoughness :: struct {
    base_colour: ResourceID,
    metallic_roughness: ResourceID,
    base_colour_factor: [4]f32,
    enable_base_colour_override: bool,
    base_colour_override: [3]f32,
    metallic_factor: f32,
    roughness_factor: f32,
}

NormalTexture :: distinct ResourceIdent
OcclusionTexture :: distinct ResourceIdent
EmissiveTexture :: distinct ResourceIdent

Clearcoat :: struct {
    clearcoat_texture: ResourceID,
    clearcoat_roughness_texture: ResourceID,
    clearcoat_normal_texture: ResourceID,
    clearcoat_factor: f32,
    clearcoat_roughness_factor: f32
}

Specular :: struct {
    specular_texture: ResourceID,
    specular_colour_texture: ResourceID,
    specular_factor: f32,
    specular_colour_factor: [3]f32
}




/*
PbrSpecularGlossiness :: cgltf.pbr_specular_glossiness
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
        Clearcoat,
        Specular
    }
}

// Assumes the resource manager is properly initialized
eno_material_from_cgltf_material :: proc(manager: ^ResourceManager, cmat: cgltf.material, gltf_file_location: string) -> (material: Material, ok: bool) {
    dbg.log(.INFO, "Converting cgltf material: %s", cmat.name)
    if cmat.name != nil do material.name = strings.clone_from_cstring(cmat.name)

    material_type: MaterialType
    if cmat.has_pbr_metallic_roughness {
        material_type.properties |= { .PBR_METALLIC_ROUGHNESS }

        met_rough := cmat.pbr_metallic_roughness

        base_tex_id: ResourceID
        if met_rough.base_color_texture.texture != nil {
            base_tex_id = texture_id_from_cgltf_texture(manager, met_rough.base_color_texture.texture, gltf_file_location) or_return
        }

        met_rough_id: ResourceID
        if met_rough.metallic_roughness_texture.texture != nil {
            met_rough_id = texture_id_from_cgltf_texture(manager, met_rough.metallic_roughness_texture.texture, gltf_file_location) or_return
        }

        metallic_roughness := PBRMetallicRoughness {
            base_colour = base_tex_id,
            metallic_roughness = met_rough_id,
            base_colour_factor = cmat.pbr_metallic_roughness.base_color_factor,
            metallic_factor = cmat.pbr_metallic_roughness.metallic_factor,
            roughness_factor = cmat.pbr_metallic_roughness.roughness_factor
        }
        material.properties[.PBR_METALLIC_ROUGHNESS] = { PBR_METALLIC_ROUGHNESS, metallic_roughness }
    }
    if cmat.normal_texture.texture != nil {
        material_type.properties |= { .NORMAL_TEXTURE }

        tex_id := texture_id_from_cgltf_texture(manager, cmat.normal_texture.texture, gltf_file_location) or_return
        material.properties[.NORMAL_TEXTURE] = { NORMAL_TEXTURE, NormalTexture(tex_id) }
    }
    if cmat.occlusion_texture.texture != nil {
        material_type.properties |= { .OCCLUSION_TEXTURE }

        tex_id := texture_id_from_cgltf_texture(manager, cmat.occlusion_texture.texture, gltf_file_location) or_return
        material.properties[.OCCLUSION_TEXTURE] = { OCCLUSION_TEXTURE, OcclusionTexture(tex_id) }
    }
    if cmat.emissive_texture.texture != nil {
        material_type.properties |= { .EMISSIVE_TEXTURE }

        tex_id := texture_id_from_cgltf_texture(manager, cmat.emissive_texture.texture, gltf_file_location) or_return
        material.properties[.EMISSIVE_TEXTURE] = { EMISSIVE_TEXTURE, EmissiveTexture(tex_id) }
    }
    if cmat.has_clearcoat {
        material_type.properties |= { .CLEARCOAT }
        clear := cmat.clearcoat

        clear_tex_id: ResourceID
        if clear.clearcoat_texture.texture != nil {
            clear_tex_id = texture_id_from_cgltf_texture(manager, clear.clearcoat_texture.texture, gltf_file_location) or_return
        }

        clear_rough_tex_id: ResourceID
        if clear.clearcoat_roughness_texture.texture != nil {
            clear_rough_tex_id = texture_id_from_cgltf_texture(manager, clear.clearcoat_roughness_texture.texture, gltf_file_location) or_return
        }

        clear_normal_tex_id: ResourceID
        if clear.clearcoat_normal_texture.texture != nil {
            clear_normal_tex_id = texture_id_from_cgltf_texture(manager, clear.clearcoat_normal_texture.texture, gltf_file_location) or_return
        }

        clearcoat := Clearcoat{
            clear_tex_id,
            clear_rough_tex_id,
            clear_normal_tex_id,
            clear.clearcoat_factor,
            clear.clearcoat_roughness_factor
        }
        material.properties[.CLEARCOAT] = MaterialProperty{ CLEARCOAT, clearcoat }
    }
    if cmat.has_specular {
        material_type.properties |= { .SPECULAR }
        spec := cmat.specular

        spec_tex_id: ResourceID
        if spec.specular_texture.texture != nil {
            spec_tex_id = texture_id_from_cgltf_texture(manager, spec.specular_texture.texture, gltf_file_location) or_return
        }

        spec_colour_tex_id: ResourceID
        if spec.specular_color_texture.texture != nil {
            spec_colour_tex_id = texture_id_from_cgltf_texture(manager, spec.specular_color_texture.texture, gltf_file_location) or_return
        }

        specular := Specular{
            spec_tex_id,
            spec_colour_tex_id,
            spec.specular_factor,
            spec.specular_color_factor
        }
        material.properties[.SPECULAR] = MaterialProperty{ SPECULAR, specular }
    }

    material.emissive_factor = cmat.emissive_factor
    material.alpha_cutoff = cmat.alpha_cutoff
    material_type.double_sided = bool(cmat.double_sided)
    material_type.unlit = bool(cmat.unlit)
    material_type.alpha_mode = cast(AlphaMode)cmat.alpha_mode

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
    uri: string,
    w, h, channels: i32,
    pixel_data: rawptr  // Can be nil for no data
}

destroy_image :: proc(image: ^Image) {
    delete(image.uri)
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
        image = load_image_from_cgltf_image(texture.image_, gltf_file_location, allocator=allocator, loc=loc) or_return,
        properties = properties_from_texture_sampler(texture.sampler, allocator)
    }, true
}

texture_id_from_cgltf_texture :: proc(
    manager: ^ResourceManager,
    texture: ^cgltf.texture,
    gltf_file_location: string,
    allocator := context.allocator,
    loc := #caller_location
) -> (result: ResourceIdent, ok: bool) {
    tex := texture_from_cgltf_texture(texture, gltf_file_location, allocator, loc) or_return

    pix_data := tex.image.pixel_data
    tex.image.pixel_data = nil

    result = add_texture(manager, tex) or_return
    t_res := get_texture(manager, result) or_return
    if t_res.image.pixel_data == nil do t_res.image.pixel_data = pix_data
    else do stbi.image_free(pix_data)

    ok = true
    return
}

properties_from_texture_sampler :: proc(sampler: ^cgltf.sampler, allocator := context.allocator) -> (properties: TextureProperties) {
    properties = default_texture_properties(allocator)
    if sampler == nil do return

    #partial switch sampler.mag_filter {
        case .nearest: properties[.MAG_FILTER] = .NEAREST
        case .linear: properties[.MAG_FILTER] = .LINEAR
        case: dbg.log(.WARN, "Sampler mag filter '%d' invalid, ignoring", sampler.mag_filter)
    }

    #partial switch sampler.min_filter {
        case .nearest: properties[.MIN_FILTER] = .NEAREST
        case .linear: properties[.MIN_FILTER] = .LINEAR
        case .nearest_mipmap_nearest: properties[.MIN_FILTER] = .NEAREST_MIPMAP_NEAREST
        case .linear_mipmap_nearest: properties[.MIN_FILTER] = .LINEAR_MIPMAP_NEAREST
        case .nearest_mipmap_linear: properties[.MIN_FILTER] = .NEAREST_MIPMAP_LINEAR
        case .linear_mipmap_linear: properties[.MIN_FILTER] = .LINEAR_MIPMAP_LINEAR
        case: dbg.log(.WARN, "Sampler min filter '%d' invalid, ignoring", sampler.min_filter)
    }

    switch sampler.wrap_s {
        case .clamp_to_edge: properties[.WRAP_S] = .CLAMP_EDGE
        case .mirrored_repeat: properties[.WRAP_S] = .MIRROR_REPEAT
        case .repeat: properties[.WRAP_S] = .REPEAT
    }

    switch sampler.wrap_t {
        case .clamp_to_edge: properties[.WRAP_T] = .CLAMP_EDGE
        case .mirrored_repeat: properties[.WRAP_T] = .MIRROR_REPEAT
        case .repeat: properties[.WRAP_T] = .REPEAT
    }
    return
}

load_image_from_cgltf_image :: proc(image: ^cgltf.image, gltf_file_location: string, allocator := context.allocator, loc := #caller_location) -> (result: Image, ok: bool) {
    if image.name != nil do result.uri = strings.clone_from_cstring(image.uri, allocator=allocator)
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


load_image_from_uri :: proc(uri: string, uri_base: string = "", flip_image := false, desired_channels: i32 = 4, as_float := false, allocator := context.allocator, loc := #caller_location) -> (result: Image, ok: bool) {

    path := len(uri_base) == 0 ? strings.clone(uri, allocator=allocator) : utils.concat(uri_base, uri, allocator=allocator);
    file_utils.check_path(path, loc=loc) or_return
    path_cstr := strings.clone_to_cstring(path, allocator=allocator); defer delete(path_cstr)

    if flip_image do stbi.set_flip_vertically_on_load(1)
    defer if flip_image do stbi.set_flip_vertically_on_load(0)

    if as_float do result.pixel_data = stbi.loadf(path_cstr, &result.w, &result.h, &result.channels, desired_channels)
    else do result.pixel_data = stbi.load(path_cstr, &result.w, &result.h, &result.channels, desired_channels)
    if result.pixel_data == nil {
        dbg.log(.ERROR, "Could not read pixel data from file: %s", uri)
        return
    }

    result.uri = path

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

// Provide material to use a specific material, if nothing is provided an unlit + base colour with light.png from resources will be used
make_light_billboard_model :: proc(
    manager: ^ResourceManager,
    material: Maybe(Material) = nil,
    colour_override: Maybe([3]f32) = nil,
    cylindrical := false,
    allocator := context.allocator
) -> (model: Model, ok: bool) {
    // Does not transfer

    model.meshes = make([dynamic]Mesh, 1, allocator=allocator)

    billboard_mesh := primitive_square_mesh_data(allocator)
    layout := primitive_square_mesh_layout(true, allocator)
    layout.shader = add_shader(manager, get_billboard_vertex_shader(cylindrical, allocator) or_return) or_return
    billboard_mesh.layout = add_vertex_layout(manager, layout) or_return
    billboard_mesh.centroid = calculate_centroid(billboard_mesh.vertex_data, layout.infos) or_return

    if material != nil do billboard_mesh.material = material.?
    else {
        base_texture_id := texture_from_path(manager, "billboard_texture", "light.png", standards.TEXTURE_RESOURCE_PATH, flip_image = true, allocator=allocator) or_return

        billboard_mesh.material.properties = make(map[MaterialPropertyInfo]MaterialProperty, allocator=allocator)
        base_colour_override := colour_override == nil ? [3]f32{ 0.0, 1.0, 0.0 } : colour_override.?
        met_rough := PBRMetallicRoughness{
            base_colour = base_texture_id,
            enable_base_colour_override = true,
            base_colour_factor = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            base_colour_override = base_colour_override,
        }
        billboard_mesh.material.properties[.PBR_METALLIC_ROUGHNESS] = MaterialProperty{ PBR_METALLIC_ROUGHNESS, met_rough }

        material_type: MaterialType
        material_type.unlit = true
        material_type.double_sided = false
        material_type.alpha_mode = .BLEND
        material_type.properties = { .PBR_METALLIC_ROUGHNESS }
        billboard_mesh.material.type = add_material(manager, material_type) or_return
    }

    model.meshes[0] = billboard_mesh

    ok = true
    return
}

get_billboard_vertex_shader :: proc(cylindrical: bool, allocator := context.allocator) -> (shader: Shader, ok: bool) {
    if cylindrical do return read_single_shader_source(standards.SHADER_RESOURCE_PATH + "billboard_cylindrical.vert", .VERTEX, allocator)
    else do return read_single_shader_source(standards.SHADER_RESOURCE_PATH + "billboard_spherical.vert", .VERTEX, allocator)
}


POINT_LIGHT_COMPONENT := standards.ComponentTemplate{ "PointLight", PointLight, size_of(PointLight) }
DIRECTIONAL_LIGHT_COMPONENT := standards.ComponentTemplate{ "DirectionalLight", DirectionalLight, size_of(DirectionalLight) }
SPOT_LIGHT_COMPONENT := standards.ComponentTemplate{ "SpotLight", SpotLight, size_of(SpotLight) }


calculate_centroid :: proc(vertex_data: VertexData, layout_infos: []MeshAttributeInfo) -> (centroid: [3]f32, ok: bool) {
    if len(vertex_data) < 3 {
        dbg.log(.ERROR, "Invalid number of vertices")
        return
    }

    total_float_stride := 0
    position_float_offset := 0
    position_found := false
    for info in layout_infos {
        if !position_found && info.type == .position {
            position_found = true
            position_float_offset = total_float_stride
        }
        total_float_stride += int(info.float_stride)
    }
    if !position_found {
        dbg.log(.ERROR, "Mesh layout infos contains no position")
        return
    }

    if len(vertex_data) % total_float_stride != 0 {
        dbg.log(.ERROR, "Invalid vertex data w.r.t. float stride")
        return
    }

    n_vertices := len(vertex_data) / total_float_stride
    c64: [3]f64

    for vi in 0..<n_vertices {
        buf_idx := vi * total_float_stride + position_float_offset
        if buf_idx + 2 >= len(vertex_data) {
            dbg.log(.ERROR, "Buffer index out of bounds")
            return
        }

        vertex := [3]f32{ vertex_data[buf_idx], vertex_data[buf_idx + 1], vertex_data[buf_idx + 2] }
        c64 += linalg.array_cast(vertex, f64)
    }

    c64 /= f64(n_vertices)
    centroid = linalg.array_cast(c64, f32)

    ok = true
    return
}