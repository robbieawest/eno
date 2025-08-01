package render

import "../resource"
import dbg "../debug"
import "../utils"

import "core:strings"
import "core:reflect"


shader_layout_from_mesh_layout :: proc(shader_info: ^resource.ShaderInfo, layout: []resource.MeshAttributeInfo) -> (ok: bool) {
    n_Attributes := len(layout)
    new_inputs := make([dynamic]resource.GLSLPair, n_Attributes)
    defer resource.destroy_glsl_pairs(new_inputs[:])

    for i: uint = 0; i < uint(n_Attributes); i += 1 {
        glsl_type := glsl_type_from_attribute(layout[i]) or_return

        name := parse_attribute_name(layout[i]) or_return
        defer delete(name)

        new_inputs[i] = resource.GLSLPair{ glsl_type, utils.concat("a_", name) }
    }

    resource.add_inputs(shader_info, ..new_inputs[:])
    ok = true
    return
}

/*
    Allocates new name
*/
parse_attribute_name :: proc(attribute_info: resource.MeshAttributeInfo, allocator := context.allocator) -> (name: string, ok: bool) {
    if len(attribute_info.name) == 0 {
        reflected_name, reflect_ok := reflect.enum_name_from_value(attribute_info.type)
        if !reflect_ok {
            dbg.log(.ERROR, "Could not get layout name")
            return
        }

        name = strings.clone(reflected_name, allocator)
    } else do name = strings.clone(attribute_info.name)

    ok = true
    return
}

glsl_type_from_attribute :: proc(attribute_info: resource.MeshAttributeInfo) -> (glsl_type: resource.GLSLDataType, ok: bool) {

    switch attribute_info.element_type {
    case .invalid:
        dbg.log(.ERROR, "Invalid attribute element type")
        return
    case .scalar: glsl_type = convert_component_type_to_glsl_type(attribute_info.data_type) or_return
    case .vec2: glsl_type = .vec2
    case .vec3: glsl_type = .vec3
    case .vec4: glsl_type = .vec4
    case .mat2: glsl_type = .mat2
    case .mat3: glsl_type = .mat3
    case .mat4: glsl_type = .mat4
    }

    ok = true
    return
}


/*
    GLTF only supports types mentioned in MeshComponentType
    GLSL does suppport some mention of precision, but I really do not care for this
*/
@(private)
convert_component_type_to_glsl_type :: proc(component_type: resource.MeshComponentType) -> (type: resource.GLSLDataType, ok: bool) {
    switch component_type {
        case .invalid, .i8, .i16, .u8, .u16:
            dbg.log(.ERROR, "Invalid component type when attempting to convert to GLSL type")
            return
        case .f32: type = .float
        case .u32: type = .uint
    }

    ok = true
    return
}


/* Todo write proper interface for typeid -> ShaderStuct later

generate_glsl_struct :: proc(type: typeid, allocator := context.allocator) -> (glsl_struct: ShaderStruct, ok: bool) {

    if !reflect.is_struct(type_info_of(type)) {
        dbg.debug_point(.ERROR, "Gotten type which does not represent a struct")
        return
    }

    return _generate_glsl_struct_recurse(type, allocator)
}

@(private)
_generate_glsl_struct_recurse :: proc(type: typeid, allocator := context.allocator) -> (glsl_struct: ^ShaderStruct, ok: bool) {

    glsl_struct = new(ShaderStruct)

    name_builder := strings.builder_make(allocator)
    _, io_err := reflect.write_typeid(&name_builder, type); if io_err != io.Error.None {
        dbg.debug_point(.ERROR, "IO Error when generating GLSL struct name")
        return
    }
    glsl_struct.name = strings.to_string(name_builder)

    field_infos := reflect.struct_fields_zipped(type)
    glsl_fields := make([dynamic]extended_glsl_type_name_pair, 0, len(field_infos))

    for field in field_infos {
        glsl_type: ExtendedGLSLType

        #partial switch _ in field.type.variant {
        case runtime.Type_Info_Struct:
            glsl_type = _generate_glsl_struct_recurse(field.type.id) or_return
        case runtime.Type_Info_Array:
            reflect.s
            field.type.flags
            glsl_type = GLSLFixedArray{ }
        case:
            glsl_type = typeid_to_glsl_type(field.type.id) or_return
        }

        type_name_pair: extended_glsl_type_name_pair = { glsl_type, field.name }
        append(&glsl_fields, type_name_pair)
    }

    glsl_struct.fields = glsl_fields[:]
    ok = true
    return
}

*/