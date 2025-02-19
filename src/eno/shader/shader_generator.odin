package gpu

import "../model"
import dbg "../debug"

import "core:strings"
import "core:reflect"
import "core:fmt"
import "core:io"

// Defines procedures for building shaders from multiple blocks of input/output
// Be careful when using these procedures if reading a shader from a file and not parsing that shader

/*
    Overwrites any shader layout already existing

*/
shader_layout_from_mesh :: proc(shader: ^ShaderInfo, mesh: model.Mesh) -> (ok: bool) {
    return shader_layout_from_mesh_layout(shader, mesh.layout)
}

shader_layout_from_mesh_layout :: proc(shader: ^ShaderInfo, layout: model.VertexLayout) -> (ok: bool) {
    n_Attributes := len(layout)
    new_layout := make([dynamic]ShaderLayout, n_Attributes)

    for i: uint = 0; i < uint(n_Attributes); i += 1 {
        glsl_type: GLSLDataType

        switch layout[i].element_type {
        case .invalid:
            dbg.debug_point(dbg.LogLevel.ERROR, "Invalid attribute element type")
            return
        case .scalar: glsl_type = convert_component_type_to_glsl_type(layout[i].data_type) or_return
        case .vec2: glsl_type = .vec2
        case .vec3: glsl_type = .vec3
        case .vec4: glsl_type = .vec4
        case .mat2: glsl_type = .mat2
        case .mat3: glsl_type = .mat3
        case .mat4: glsl_type = .mat4
        }

        name := layout[i].name
        if len(name) == 0 {
            name, ok = reflect.enum_name_from_value(layout[i].type)
            if !ok {
                dbg.debug_point(dbg.LogLevel.ERROR, "Could not get layout name")
                return
            }
        }
        new_layout[i] = ShaderLayout{ i, glsl_type, name }
    }

    shader.layout = new_layout
    ok = true
    return
}


/*
    GLTF only supports types mentioned in MeshComponentType
    GLSL does suppport some mention of precision, but I really do not care for this
*/
@(private)
convert_component_type_to_glsl_type :: proc(component_type: model.MeshComponentType) -> (type: GLSLDataType, ok: bool) {
    switch component_type {
        case .invalid, .i8, .i16, .u8, .u16:
            dbg.debug_point(dbg.LogLevel.ERROR, "Invalid component type when attempting to convert to GLSL type")
            return
        case .f32: type = .float
        case .u32: type = .uint
    }

    ok = true
    return
}


generate_glsl_struct :: proc(type: typeid, allocator := context.allocator) -> (glsl_struct: ShaderStruct) {

    if !reflect.is_struct(type_info_of(type)) {
        dbg.debug_point(dbg.LogLevel.ERROR, "Gotten type which does not represent a struct")
        return
    }

    name_builder := strings.builder_make(allocator)
    _, io_err := reflect.write_typeid(&name_builder, type); if io_err != io.Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "IO Error when generating GLSL struct name")
        return
    }
    glsl_struct.name = strings.to_string(name_builder)

    field_infos := reflect.struct_fields_zipped(type)
    for field in field_infos {
        // todo write code for converting typeid to glsl data type
    }
}