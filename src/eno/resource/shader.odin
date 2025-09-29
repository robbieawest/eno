package resource

import gl "vendor:OpenGL"

import dbg "../debug"
import "../utils"
import futils "../file_utils"

import "base:runtime"
import "core:strings"
import "core:mem"
import "core:fmt"
import "core:reflect"
import "core:slice"
import "core:os"
import "core:log"
import glm "core:math/linalg/glsl"

/*
    File for everything shaders
    Todo:
        Support for const glsl types
        Control for shader version
*/

ShaderStructID :: string

// Defines a generalized shader structure which then compiles using the given render API
GLSLType :: union #no_nil {
    ShaderStructID,  // References a shader struct, therefore no ownership assumed
    GLSLDataType,
}

ExtendedGLSLType :: union #no_nil {
    ShaderStructID,
    GLSLDataType,
    GLSLFixedArray,
    GLSLVariableArray
}

/*
destroy_extended_glsl_type :: proc(type: ExtendedGLSLType) {
    #partial switch v in type {
        case GLSLFixedArray: free(v)
        case GLSLVariableArray: free(v)
    }
}
*/


GLSLFixedArray :: struct {
    size: uint,
    type: GLSLType
}

GLSLVariableArray :: struct {
    type: GLSLType
}


GLSLPair :: struct {
    type: GLSLType,
    name: string  // Assumes ownership
}


copy_glsl_pair :: proc(pair: GLSLPair) -> GLSLPair {
    return GLSLPair{ pair.type, strings.clone(pair.name) }
}

destroy_glsl_pair :: proc{ destroy_glsl_pair_norm, destroy_glsl_pair_extended }

@(private)
destroy_glsl_pair_norm :: proc(pair: GLSLPair) {
    delete(pair.name)
}


ExtendedGLSLPair :: struct {
    type: ExtendedGLSLType,
    name: string
}

copy_extended_glsl_pair :: proc(pair: ExtendedGLSLPair) -> ExtendedGLSLPair {
    return ExtendedGLSLPair{ pair.type, strings.clone(pair.name) }
}

destroy_glsl_pair_extended :: proc(pair: ExtendedGLSLPair, allocator := context.allocator) {
    delete(pair.name, allocator)
    // destroy_extended_glsl_type(pair.type)
}

destroy_glsl_pairs :: proc{ destroy_glsl_pairs_norm, destroy_glsl_pairs_extended }

destroy_glsl_pairs_norm :: proc(pairs: []GLSLPair) {
    for pair in pairs do destroy_glsl_pair_norm(pair)
    delete(pairs)
}

destroy_glsl_pairs_extended :: proc(pairs: []ExtendedGLSLPair) {
    for pair in pairs do destroy_glsl_pair_extended(pair)
    delete(pairs)
}

// Shader Info

ShaderInfo :: struct {
    bindings: ShaderBindings,
    inputs: [dynamic]GLSLPair,
    outputs: [dynamic]GLSLPair,
    uniforms: [dynamic]GLSLPair,
    structs: [dynamic]ShaderStruct,
    functions: [dynamic]ShaderFunction
}

make_shader_info :: proc(allocator := context.allocator) -> ShaderInfo {
    return {
        ShaderBindings{ make([dynamic]ShaderBufferObject, allocator=allocator), make([dynamic]ShaderBufferObject, allocator=allocator) },
        make([dynamic]GLSLPair, allocator=allocator),
        make([dynamic]GLSLPair, allocator=allocator),
        make([dynamic]GLSLPair, allocator=allocator),
        make([dynamic]ShaderStruct, allocator=allocator),
        make([dynamic]ShaderFunction, allocator=allocator)
    }
}

destroy_shader_info :: proc(shader: ShaderInfo) {
    destroy_shader_bindings(shader.bindings)

    destroy_glsl_pairs(shader.inputs[:])
    destroy_glsl_pairs(shader.outputs[:])
    destroy_glsl_pairs(shader.uniforms[:])

    for shader_struct in shader.structs do destroy_shader_struct(shader_struct)
    delete(shader.structs)

    for function in shader.functions do destroy_shader_function(function)
    delete(shader.functions)
}

//

ShaderStruct :: struct {
    name: string,  // Asssumes ownership
    fields: []ExtendedGLSLPair
};

make_shader_struct :: proc(name: string, fields: ..ExtendedGLSLPair) -> ShaderStruct {
    new_fields := make([]ExtendedGLSLPair, len(fields))
    for i := 0; i < len(fields); i += 1 {
        new_fields[i] = copy_extended_glsl_pair(fields[i])
    }
    return ShaderStruct{ strings.clone(name), new_fields }
}

copy_shader_struct :: proc(shader_struct: ShaderStruct) -> ShaderStruct {
    return make_shader_struct(shader_struct.name, ..shader_struct.fields)
}

destroy_shader_struct :: proc(shader_struct: ShaderStruct) {
    delete(shader_struct.name)
    destroy_glsl_pairs(shader_struct.fields)
}


// Shader Functions

ShaderFunction :: struct {
    return_type: GLSLType,
    arguments: []GLSLPair,
    label: string,
    source: FunctionSource
};

FunctionSource :: []string
make_function_source :: proc(lines: []string) -> FunctionSource {
    new_lines := make([]string, len(lines))
    for i := 0; i < len(lines); i += 1 {
        new_lines[i] = strings.clone(lines[i])
    }
    return new_lines
}
copy_function_source :: make_function_source

destroy_function_source :: proc(source: FunctionSource) {
    for line in source do delete(line)
    delete(source)
}

make_shader_function :: proc(ret_type: GLSLType, label: string, source: FunctionSource, arguments: ..GLSLPair) -> (function: ShaderFunction) {
    return copy_shader_function(ShaderFunction{ ret_type, arguments, label, source })
}

copy_shader_function :: proc(func: ShaderFunction) -> ShaderFunction {
    new_arguments := make([]GLSLPair, len(func.arguments))
    for i := 0; i < len(func.arguments); i += 1 {
        new_arguments[i] = copy_glsl_pair(func.arguments[i])
    }
    return { func.return_type, new_arguments, strings.clone(func.label), copy_function_source(func.source) }
}

destroy_shader_function :: proc(function: ShaderFunction) {
    destroy_function_source(function.source)
    delete(function.label)
    destroy_glsl_pairs(function.arguments)
}

//


// Shader Bindings

// Only supporting UBOs and SSBOs for now
BindingType :: enum{ UBO, SSBO }
ShaderBindings :: struct {
    uniform_buffer_objects: [dynamic]ShaderBufferObject,
    shader_storage_buffer_objects: [dynamic]ShaderBufferObject,
}

destroy_shader_bindings :: proc(binding: ShaderBindings) {
    for ubo in binding.uniform_buffer_objects do destroy_shader_buffer_object(ubo)
    for ssbo in binding.shader_storage_buffer_objects do destroy_shader_buffer_object(ssbo)
    delete(binding.uniform_buffer_objects)
    delete(binding.shader_storage_buffer_objects)
}

ShaderBufferObject :: struct {
    name: string,
    fields: []ExtendedGLSLPair
}

copy_shader_buffer_object :: proc(obj: ShaderBufferObject) -> ShaderBufferObject {
    new_fields := make([]ExtendedGLSLPair, len(obj.fields))
    for i := 0; i < len(obj.fields); i += 1 {
        new_fields[i] = ExtendedGLSLPair{ obj.fields[i].type, strings.clone(obj.fields[i].name) }
    }
    return ShaderBufferObject{ strings.clone(obj.name), new_fields }
}

shader_buffer_object_to_str :: proc(shader_info: ShaderInfo, obj: ShaderBufferObject) -> (result: string, ok: bool) {
    builder := strings.builder_make()
    fmt.sbprintf(&builder, "%s {{\n", obj.name)

    for field in obj.fields {
        s_type := extended_glsl_type_to_string(shader_info, field.type) or_return
        defer delete(s_type)
        fmt.sbprintf(&builder, "\t%s %s;", s_type, field.name)
    }

    strings.write_string(&builder, "\n}")
    return strings.to_string(builder), true
}

destroy_shader_buffer_object :: proc(obj: ShaderBufferObject) {
    delete(obj.name)
    destroy_glsl_pairs(obj.fields)
}


// Procs to handle shader fields, these deeply take ownership of input

add_bindings_of_type :: proc(shader: ^ShaderInfo, type: BindingType, buffer_objects: ..ShaderBufferObject) -> (ok: bool) {

    exist_objects: ^[dynamic]ShaderBufferObject
    switch type {
        case .UBO: exist_objects = &shader.bindings.uniform_buffer_objects
        case .SSBO: exist_objects = &shader.bindings.shader_storage_buffer_objects
    }

    err := reserve(exist_objects, len(buffer_objects)); if err != mem.Allocator_Error.None {
        dbg.log(.ERROR, "Could not allocate memory for bindings")
        return
    }

    for buffer_object in buffer_objects {
        for exist_object in exist_objects {
            if strings.compare(buffer_object.name, exist_object.name) == 0 {
                dbg.log(.ERROR, "Attempting to add duplicate binding name: %s", buffer_object.name)
                return
            }
        }

        append(exist_objects, copy_shader_buffer_object(buffer_object))
    }

    ok = true
    return
}


add_inputs :: proc(shader: ^ShaderInfo, inputs: ..GLSLPair) -> (ok: bool) {
    return add_io(shader, true, ..inputs)
}

add_outputs :: proc(shader: ^ShaderInfo, inputs: ..GLSLPair) -> (ok: bool) {
    return add_io(shader, false, ..inputs)
}

@(private)
add_io :: proc(shader: ^ShaderInfo, is_input: bool, ios: ..GLSLPair) -> (ok: bool) {

    exist_ios := is_input ? &shader.inputs : &shader.outputs

    err := reserve(exist_ios, len(ios)); if err != mem.Allocator_Error.None {
        dbg.log(.ERROR, "Could not allocate memory for new inputs")
        return
    }

    for io in ios {
        for exist_ios in exist_ios {
            if strings.compare(io.name, exist_ios  .name) == 0 {
                if is_input do dbg.log(.ERROR, "Attempting to add duplicate input name: %s", io.name)
                else do dbg.log(.ERROR, "Attempting to add duplicate output name: %s", io.name)
                return
            }
        }

        append(exist_ios, GLSLPair{ io.type, strings.clone(io.name) })
    }

    ok = true
    return
}


add_uniforms :: proc(shader: ^ShaderInfo, uniforms: ..GLSLPair) -> (ok: bool) {
    err := reserve(&shader.uniforms, len(uniforms)); if err != mem.Allocator_Error.None {
        dbg.log(.ERROR, "Could not allocate uniforms")
        return
    }

    for uniform in uniforms {
        err = add_uniform(shader, uniform); if err != mem.Allocator_Error.None {
            dbg.log(.ERROR, "Could not allocate uniforms")
            return
        }
    }

    ok = true
    return
}

@(private)
add_uniform :: proc(shader: ^ShaderInfo, new_uniform: GLSLPair) -> (err: mem.Allocator_Error) {
    for uniform in shader.uniforms {
        if strings.compare(uniform.name, new_uniform.name) == 0 {
            dbg.log(.ERROR, "Attempting to add duplicate uniform name: %s", uniform.name)
            return
        }
    }

    _ = append(&shader.uniforms, GLSLPair{ new_uniform.type, strings.clone(new_uniform.name) }
    ) or_return

    return
}


add_structs :: proc(shader: ^ShaderInfo, structs: ..ShaderStruct) -> (ok: bool) {
    err := reserve(&shader.structs, len(structs)); if err != mem.Allocator_Error.None {
        dbg.log(.ERROR, "Could not allocate structs")
        return
    }

    for shader_struct in structs {
        ok = add_struct(shader, shader_struct); if !ok {
            dbg.log(.ERROR, "Could not allocate structs")
            return
        }
    }

    ok = true
    return
}

@(private)
add_struct :: proc(shader: ^ShaderInfo, new_struct: ShaderStruct) -> (ok: bool) {

    for shader_struct in shader.structs {
        if strings.compare(shader_struct.name, new_struct.name) == 0 {
            dbg.log(.ERROR, "Attempting to add duplicate struct name: %s", shader_struct.name)
            return
        }
    }

    _, err := append(&shader.structs, new_struct)

    return err == .None
}


add_functions :: proc(shader: ^ShaderInfo, functions: ..ShaderFunction) -> (ok: bool) {
    err := reserve(&shader.functions, len(functions)); if err != mem.Allocator_Error.None {
        dbg.log(.ERROR, "Could not allocate functions")
        return
    }

    for function in functions {
        ok = add_function(shader, function); if !ok {
            dbg.log(.ERROR, "Could not allocate functions")
            return
        }
    }

    ok = true
    return
}

@(private)
add_function :: proc(shader: ^ShaderInfo, new_function: ShaderFunction) -> (ok: bool) {
    for function in shader.functions {
        if strings.compare(function.label, new_function.label) == 0 {
            dbg.log(.ERROR, "Attempting to add duplicate function label: %s", function.label)
            return
        }
    }

    _, err := append(&shader.functions, new_function)
    return err == .None
}

//

ShaderType :: enum { // Is just gl.Shader_Type
    NIL,
    LINK,
    VERTEX,
    COMPUTE,
    FRAGMENT,
    GEOMETRY,
    TESS_CONTROL,
    TESS_EVALUATION
}

Shader :: struct {
    type: ShaderType,
    id: ShaderIdentifier,
    source: ShaderSource
}

destroy_shader :: proc(shader: Shader) {
    destroy_shader_source(shader.source)
}


ShaderSource :: struct {
    is_available_as_string: bool,
    shader_info: ShaderInfo,
    string_source: string
}

destroy_shader_source :: proc(source: ShaderSource) {
    if source.is_available_as_string && len(source.string_source) != 0 do delete(source.string_source)
    destroy_shader_info(source.shader_info)
}


ShaderIdentifier :: Maybe(u32)

ShaderProgram :: struct {
    id: ShaderIdentifier,
    shaders: map[ShaderType]ResourceIdent,  // Although it is possible to add more than one shader of each type, adding support really doesn't mean anything
    uniform_cache: ShaderUniformCache
}


init_shader_program :: proc(allocator := context.allocator) -> (program: ShaderProgram) {
    program.shaders = make(map[ShaderType]ResourceIdent, allocator=allocator)
    program.uniform_cache = make(ShaderUniformCache, allocator=allocator)
    return
}

// Does not copy incoming shaders
make_shader_program:: proc(manager: ^ResourceManager, shaders: []Shader, allocator := context.allocator) -> (program: ShaderProgram, ok: bool) {
    program.shaders = make(map[ShaderType]ResourceIdent, allocator=allocator)
    program.uniform_cache = make(ShaderUniformCache, allocator=allocator)
    add_shaders_to_program(manager, &program, shaders) or_return
    ok = true
    return
}


// Does not copy incoming shaders
add_shaders_to_program :: proc(manager: ^ResourceManager, program: ^ShaderProgram, shaders: []Shader) -> (ok: bool) {
    for shader in shaders {
        if shader.type in program.shaders {
            dbg.log(.WARN, "Shader of existing type attempted to be added to program, ignoring")
        } else do program.shaders[shader.type] = add_shader(manager, shader) or_return
    }
    return true
}

destroy_shader_program :: proc(manager: ^ResourceManager, program: ShaderProgram) -> (ok: bool) {
    for _, shader in program.shaders do remove_shader(manager, shader) or_return
    delete(program.shaders)
    delete(program.uniform_cache)
    return true
}


// Deserializing/building a shader script (string representation)

conv_gl_shader_type :: proc(type: ShaderType) -> gl.Shader_Type {  // Likely could use ordinality
    switch (type) {
    case .NIL:
        return .NONE
    case .LINK:
        return .SHADER_LINK
    case .VERTEX:
        return .VERTEX_SHADER
    case .COMPUTE:
        return .COMPUTE_SHADER
    case .FRAGMENT:
        return .FRAGMENT_SHADER
    case .GEOMETRY:
        return .GEOMETRY_SHADER
    case .TESS_CONTROL:
        return .TESS_CONTROL_SHADER
    case .TESS_EVALUATION:
        return .TESS_EVALUATION_SHADER
    }
    return .NONE
}


// Does not copy incoming shader_info
build_shader_from_source :: proc(shader_info: ShaderInfo, type: ShaderType) -> (shader: Shader, ok: bool) {
    shader.source.shader_info = shader_info
    ok = supply_shader_source(&shader)
    return
}

/*
    Builds/Deserializes the source as a single string with newlines
    Uses glsl version 430 core
*/
supply_shader_source :: proc(shader: ^Shader, allocator := context.allocator) -> (ok: bool) {
    old_alloc := context.allocator
    context.allocator = allocator
    defer context.allocator = old_alloc

    dbg.log(.INFO, "Building Shader Source")
    shader_info := shader.source.shader_info
    type := shader.type

    builder, err := strings.builder_make(); if err != mem.Allocator_Error.None {
        dbg.log(.ERROR, "Allocator error while building shader source")
        return
    }

    strings.write_string(&builder, "#version 430 core\n")
    strings.write_string(&builder, "\n")

    for ssbo, i in shader_info.bindings.shader_storage_buffer_objects {
        buf_str := shader_buffer_object_to_str(shader_info, ssbo) or_return
        defer delete(buf_str)
        fmt.sbprintfln(&builder, "layout (std430, binding = %d) buffer %s", i, buf_str)
        strings.write_string(&builder, "\n")
    }

    for ubo, i in shader_info.bindings.uniform_buffer_objects {
        buf_str := shader_buffer_object_to_str(shader_info, ubo) or_return
        defer delete(buf_str)

        fmt.sbprintfln(&builder, "layout (std430, binding = %d) uniform %s", buf_str)
        strings.write_string(&builder, "\n")
    }

    for input, i in shader_info.inputs {
        s_type := glsl_type_to_string(shader_info, input.type) or_return
        defer delete(s_type)
        fmt.sbprintfln(&builder, "layout (std430, location = %d) in %s %s;", i, s_type, input.name)
    }

    strings.write_string(&builder, "\n")

    for output, i in shader_info.outputs {
        s_type := glsl_type_to_string(shader_info, output.type) or_return
        defer delete(s_type)
        fmt.sbprintfln(&builder, "layout (std430, location = %d) out %s %s;", i, s_type, output.name)
    }

    strings.write_string(&builder, "\n")

    for uniform in shader_info.uniforms {
        s_type := glsl_type_to_string(shader_info, uniform.type) or_return
        defer delete(s_type)
        fmt.sbprintfln(&builder, "uniform %s %s;", s_type, uniform.name)
    }

    strings.write_string(&builder, "\n")

    for struct_definition in shader_info.structs {
        fmt.sbprintfln(&builder, "struct %s {{", struct_definition.name)
        for field in struct_definition.fields {
            s_type := extended_glsl_type_to_string(shader_info, field.type) or_return
            defer delete(s_type)
            fmt.sbprintfln(&builder, "\t%s %s;", s_type, field.name)
        }
        fmt.sbprintfln(&builder, "}};")
        strings.write_string(&builder, "\n")
    }

    for function in shader_info.functions {
        strings.write_string(&builder, "\n")
        s_type := glsl_type_to_string(shader_info, function.return_type) or_return
        defer delete(s_type)

        fmt.sbprintf(&builder, "%s %s(", s_type, function.label)
        for argument, i in function.arguments {
            s_arg_type := glsl_type_to_string(shader_info, argument.type) or_return
            defer delete(s_arg_type)

            fmt.sbprintf(&builder, "%s %s", s_arg_type, argument.name)
            if i != len(function.arguments) - 1 do strings.write_string(&builder, ",")
        }

        fmt.sbprintf(&builder, ") {{\n")
        for line in function.source {
            fmt.sbprintf(&builder, "\t%s\n", line)
        }
        fmt.sbprintf(&builder, "}}")
    }


    shader.source.string_source = strings.to_string(builder)
    shader.source.is_available_as_string = true

    return true
}

// ToDo support for const
GLSLDataType :: enum {
    void,
    int,
    uint,
    float,
    double,
    bool,
    vec2,
    vec3,
    vec4,
    ivec2,
    ivec3,
    ivec4,
    bvec2,
    bvec3,
    bvec4,
    mat2,
    mat3,
    mat4,
    mat2x2,
    mat2x3,
    mat2x4,
    mat3x2,
    mat3x3,
    mat3x4,
    mat4x2,
    mat4x3,
    mat4x4,
    dmat2,
    dmat3,
    dmat4,
    dmat2x2,
    dmat2x3,
    dmat2x4,
    dmat3x2,
    dmat3x3,
    dmat3x4,
    dmat4x2,
    dmat4x3,
    dmat4x4,
    sampler1D,
    sampler2D,
    sampler3D,
    samplerCube,
    sampler2DShadow
}

typeid_to_glsl_type :: proc(type: typeid) -> (glsl_type: GLSLDataType, ok: bool) {
    switch type {
        case int, i32: glsl_type =.int
        case uint, u32: glsl_type = .uint
        case f32: glsl_type = .float
        case f64: glsl_type = .double
        case bool: glsl_type =.bool
        case glm.vec2: glsl_type = .vec2
        case glm.vec3: glsl_type = .vec3
        case glm.vec4: glsl_type = .vec4
        case glm.mat2: glsl_type = .mat2
        case glm.mat3: glsl_type = .mat3
        case glm.mat4: glsl_type = .mat4
        case glm.mat2x3: glsl_type = .mat2x3
        case glm.mat2x4: glsl_type = .mat2x4
        case glm.mat3x2: glsl_type = .mat3x2
        case glm.mat3x4: glsl_type = .mat3x4
        case glm.mat4x3: glsl_type = .mat4x3
        case glm.mat4x2: glsl_type = .mat4x2
        case:
            dbg.log(dbg.LogLevel.ERROR, "Unconvertable GLSL type: %v", type)
            return
    }

    ok = true
    return
}

@(private)
shader_struct_id_to_string :: proc(shader_info: ShaderInfo, id: ShaderStructID, loc := #caller_location) -> (result: string, ok: bool) {
    shader_struct: Maybe(ShaderStruct)
    for exist_struct in shader_info.structs {
        if strings.compare(exist_struct.name, id) == 0 {
            shader_struct = exist_struct
        }
    }

    if shader_struct == nil {
        dbg.log(dbg.LogLevel.ERROR, "Shader struct identifier does not match with a struct in the shader info: %s", id)
        return
    }
    return shader_struct_out_name(shader_struct.(ShaderStruct), loc), true
}

/*
    Returns allocation ownership, caller is responsible for the deallocation
*/
glsl_type_to_string :: proc(shader_info: ShaderInfo, type: GLSLType, loc := #caller_location) -> (result: string, ok: bool) {

    switch v in type {
        case ShaderStructID:
            result = shader_struct_id_to_string(shader_info, v, loc) or_return
        case GLSLDataType:
            result = glsl_data_type_to_str(v, loc)
    }

    ok = true
    return
}


/*
    Returns allocation ownership, caller is responsible for the deallocation
*/
extended_glsl_type_to_string :: proc(shader_info: ShaderInfo, type: ExtendedGLSLType, loc := #caller_location) -> (result: string, ok: bool) {

    switch v in type {
        case ShaderStructID:
            result = shader_struct_id_to_string(shader_info, v) or_return
        case GLSLDataType:
            result = glsl_data_type_to_str(v, loc)
        case GLSLFixedArray:
            s_type := glsl_type_to_string(shader_info, v.type, loc) or_return
            defer delete(s_type)

            result = fmt.aprintf("%s[%d]", s_type, v.size)  // This allocates
        case GLSLVariableArray:
            s_type := glsl_type_to_string(shader_info, v.type, loc) or_return
            defer delete(s_type)
            result = utils.concat(s_type, "[]")  // This allocates
    }

    ok = true
    return
}

@(private)
glsl_data_type_to_str :: proc(type: GLSLDataType, loc: runtime.Source_Code_Location) -> (result: string) {
    s_type, invalid_enum := reflect.enum_name_from_value(type); if !invalid_enum {
        dbg.log(dbg.LogLevel.ERROR, "Internal invalid enum error", loc=loc)
        result = strings.clone("*INTERNAL ERROR*")  // Ignore err
    }

    err: mem.Allocator_Error
    result, err = strings.clone(s_type); if err != mem.Allocator_Error.None {
        dbg.log(dbg.LogLevel.ERROR, "Failed to allocate type as string", loc=loc)
        result = strings.clone("*FAILED TO ALLOCATE*")  // Ignore err
    }

    return
}

@(private)
shader_struct_out_name :: proc(shader_struct: ShaderStruct, loc: runtime.Source_Code_Location) -> (result: string) {
    err: mem.Allocator_Error
    result, err = strings.clone(shader_struct.name); if err != mem.Allocator_Error.None {
        dbg.log(dbg.LogLevel.ERROR, "Failed to allocate type as string", loc=loc)
        result = strings.clone("*FAILED TO ALLOCATE*")  // Ignore err
    }

    return
}


/*
    Implementations for shader file reading and parsing
    A shader source does not need to have a valid serialized Shader instance attached to it, it can be a single whole source as well.
*/

ACCEPTED_SHADER_EXTENSIONS :: []string{ "frag", "vert" }


@(private)
extension_to_shader_type :: proc(ext: string) -> (type: ShaderType) {
    switch ext {
    case "vert": type = .VERTEX
    case "frag": type = .FRAGMENT
    }
    return
}

/*
ShaderReadFlag :: enum {
    Parse,
    Express
}; ShaderReadFlags :: bit_set[ShaderReadFlag]
*/

ShadingLanguage :: enum {
    GLSL,
    HLSL,
    // ...
}


ShaderPath :: struct {
    directory: string,
    filename: string
}

@(private)
init_shader_source :: proc(source: string, extension: string, allocator := context.allocator) -> (shader: Shader, ok: bool) {
    shader_type := extension_to_shader_type(extension)
    source := ShaderSource{ string_source = strings.clone(source, allocator), is_available_as_string = true}
    shader = Shader{ source = source, type = shader_type}

    /*
    if flags.Parse {
        shader.source.shader_info = parse_shader_source(shader.source.string_source) or_return
        shader.source.is_available_as_string = true
    }
    */

    ok = true
    return
}


read_single_shader_source :: proc(full_path: string, shader_type: ShaderType, allocator := context.allocator, loc := #caller_location) -> (shader: Shader, ok: bool) {
    dbg.log(dbg.LogLevel.INFO, "Reading single shader source: %s", full_path, loc=loc)
    source, err := futils.read_file_source(full_path, allocator)
    if err != .None {
        dbg.log(dbg.LogLevel.ERROR, "Could not read file source for shader of path '%s'", full_path, loc=loc)
        return
    }

    shader.source.string_source = source
    shader.source.is_available_as_string = true // Wtf even is this flag, you can just check the length of the string

    shader.type = shader_type
    ok = true
    return
}

read_shader_source :: proc(manager: ^ResourceManager, filenames: ..string, allocator := context.allocator) -> (program: ShaderProgram, ok: bool) {

    shaders := make([dynamic]Shader, allocator=allocator)
    defer delete(shaders)

    for filename in filenames {
        inv_filename := utils.regex_match(filename, utils.REGEX_FILEPATH_PATTERN)
        if inv_filename {
            dbg.log(dbg.LogLevel.ERROR, "Filepath contains invalid characters: %s", filename)
            return
        }
        dbg.log(dbg.LogLevel.INFO, "Reading shader source at path: %s", filename)

        last_ellipse_location := strings.last_index(filename, ".")
        if last_ellipse_location != -1 && !strings.contains(filename[last_ellipse_location:], "/") {
            // Extension given
            extension := filename[last_ellipse_location+1:]

            if slice.contains(ACCEPTED_SHADER_EXTENSIONS, extension) {
                source, err := futils.read_file_source(filename); defer delete(source);
                handle_file_read_error(filename, err) or_return

                append(&shaders , init_shader_source(source, extension) or_return)
            }
            else {
                dbg.log(dbg.LogLevel.ERROR, "Shader extension not accepted: %s", extension)
                return
            }
        }
        else {
            // Extension not given
            file_found := false
            for extension in ACCEPTED_SHADER_EXTENSIONS {
                full_path := utils.concat(filename, ".", extension, allocator=allocator); defer delete(full_path)
                source, err := futils.read_file_source(full_path, allocator); defer delete(source)

                if err == .None {
                    dbg.log(dbg.LogLevel.INFO, "Successfully read file. File path: \"%s\"", full_path)
                    append(&shaders , init_shader_source(source, extension, allocator) or_return)
                    file_found = true
                }
                else if err == .FileReadError {
                    file_found = true
                    dbg.log(dbg.LogLevel.ERROR, "Error occurred while reading the contents of file. Filename: \"%s\"", full_path)
                    return
                }
            }

            if !file_found {
                cwd := os.get_current_directory()
                defer delete(cwd)
                dbg.log(dbg.LogLevel.ERROR, "File could not be found from the current directory. File path: \"%s\", Current directory: \"%s\"", filename, cwd)
                return
            }
        }

    }

    if len(shaders ) == 0 {
        dbg.log(dbg.LogLevel.ERROR, "Failed to read any shader file sources")
        return
    }

    program = make_shader_program(manager, shaders[:], allocator) or_return

    ok = true
    return
}

@(private)
handle_file_read_error :: proc(filepath: string, err: futils.FileReadError, loc := #caller_location) -> (ok: bool) {
    ok = true

    message: string; level: dbg.LogLevel = .ERROR
    switch err {
    case .PathDoesNotResolve:
        message = "Could not resolve file path"
        ok = false
    case .FileReadError:
        message = "Error while reading contents of file"
        ok = false
    case .None:
        message = "Successfully read file"
        level = .INFO
    }
    dbg.log(level, "%s. File path: \"%s\"", message, filepath, loc = loc)

    return
}

// Defines must be GLSL syntax correct, responsibility is on caller
add_shader_defines :: proc(source: string, defines : ..string, allocator := context.allocator) -> (new_source: string, ok: bool) {
    first_newline_idx := -1
    for char, i in source {
        if char == '\n' {
            first_newline_idx = i
            break
        }
    }
    if first_newline_idx == -1 {
        dbg.log(.ERROR, "Must be more than one line in source")
        return
    }

    defines_str := strings.builder_make()
    defer strings.builder_destroy(&defines_str)
    for define in defines do fmt.sbprintf(&defines_str, "%s\n", define)
    new_source = utils.concat(source[0:first_newline_idx+1], strings.to_string(defines_str), source[first_newline_idx+1:], allocator=allocator)

    ok = true
    return
}

// add_shader_includes :: proc()

/* Old
// Directory must end in a slash
ShaderReadDirectories := [dynamic]string{ "./", "./shaders/", "./resources/shaders/" }
add_shader_directory :: proc(dir: string) {  // May not be thread safe
    if !slice.contains(ShaderReadDirectories[:], dir) do append(&ShaderReadDirectories, dir)
}

read_shader_source :: proc(flags: ShaderReadFlags, filepaths: ..string) -> (program: ShaderProgram, ok: bool) {
    // Whole thing is pretty sphagetti

    source_type_map: map[string]ShaderType
    for filepath in filepaths {
        for directory in ShaderReadDirectories {
            if directory[len(directory) - 1] != '/' && directory[len(directory) - 1] != '\\' {
                dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Directory must end with a slash, skipping. Directory: %s", directory), level = .ERROR })
                continue
            }

            filepath_to_check := fmt.aprintf("%s%s", directory, filepath)

            split_filepath := strings.split(filepath, ".")
            given_extension: string
            if len(split_filepath) == 0 {
                dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Directory invalid, skipping. Directory: %s", directory), level = .ERROR })
                continue
            }
            if len(split_filepath) == 2 do given_extension = split_filepath[1]

            source, path, type, err := check_shader_filepath(filepath_to_check, given_extension)

            read_ok := handle_shader_read_error(path, err)
            if read_ok do source_type_map[source] = type
        }

    }
    if len(source_type_map) == 0 {
        dbg.debug_point(dbg.LogInfo{ msg = "Failed to read any shaders", level = .ERROR })
        return
    }

    shader_sources: [dynamic]ShaderSource
    for source, type in source_type_map {
        shader_source: ShaderSource
        shader_source.type = type; shader_source.source = source; shader_source.is_serialized = flags.Parse

        if flags.Parse do shader_source.shader = parse_shader_source(source, flags) or_return

        append(&shader_sources, shader_source)
    }
    program = init_shader_program(shader_sources[:])
    if flags.Express {
        express_shader(&program)
    }

    ok = true
    return
}

// needs to return multiple for each extension
@(private = "file")
check_shader_filepath :: proc(filepath: string, extension: string) -> (sources: []string, paths: []string, shader_type: ShaderType, err: utils.FileError) {
    err = utils.FileReadError.None
    filepath := filepath
    check_extension_validity := false

    extensions: []string
    if len(extension) != 0 {
        extensions = []string{ extension }
        check_extension_validity = true
    }
    else do extensions = ACCEPTED_SHADER_EXTENSIONS


    found_filepath: string; found_extension: string
    file_handle: os.Handle;
    defer os.close(file_handle)  // Ignore error on defer
    found_file := false

    for extension in extensions {
        filepath_to_check := fmt.aprintf("%s.%s", filepath, extension)

        handle, os_path_err := os.open(filepath_to_check);
        if os_path_err == os.ERROR_NONE {
            file_handle = handle
            found_filepath = filepath_to_check
            found_file = true
            found_extension = extension

            break
        }
    }
    if !found_file {
        err = utils.FileReadError.PathDoesNotResolve
        return
    }

    if check_extension_validity && slice.contains(ACCEPTED_SHADER_EXTENSIONS, found_extension) {
        dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Shader extension not accepted: %s", found_extension), level = .ERROR })
        return
    }

    source, err = utils.read_source_from_handle(file_handle);
    shader_type = extension_to_shader_type(found_extension)
    path = found_filepath
    return
}


@(private)
handle_shader_read_error :: proc(filepath: string, err: utils.FileError, loc := #caller_location) -> (ok: bool) {
    ok = true

    switch error in err {
        case mem.Allocator_Error:
            dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Allocator error while trying to read file. File path: \"%s\"", filepath)}, loc)
            ok = false
        case utils.FileReadError:
            message: string; level: dbg.LogLevel = .ERROR

            switch error {
            case .PathDoesNotResolve:
                ok = false
                return
            case .FileReadError:
                message = "Error while reading contents of file"
                ok = false
            case .PartialFileReadError:
                message = "File could only partially be read"
                ok = false
                level = .WARN
            case .None:
                message = "Successfully read file"
                level = .INFO
            }

            dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("%s. File path: \"%s\"", message, filepath), level = level}, loc)
    }

    return
}
*/
