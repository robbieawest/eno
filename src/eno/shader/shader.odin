package gpu

import gl "vendor:OpenGL"

import dbg "../debug"
import "../utils"
import futils "../file_utils"

import "core:strings"
import "core:mem"
import "core:fmt"
import "core:reflect"
import "core:slice"
import "core:os"
import glm "core:math/linalg/glsl"

/*
    File for everything shaders
    Todo:
        Support for const glsl types
        Control for shader version
*/



// Defines a generalized shader structure which then compiles using the given render API

ExtendedGLSLType :: union {
    ShaderStruct,
    GLSLDataType
}

glsl_type_name_pair :: struct{
    type: ExtendedGLSLType,
    name: string
}


ShaderBinding :: struct {
    location: uint,
    type: enum{ BOUND_INPUT, BOUND_OUTPUT },
    data_type: ExtendedGLSLType,
    name: string,
}


ShaderInput :: glsl_type_name_pair
ShaderOutput :: glsl_type_name_pair
ShaderUniform :: glsl_type_name_pair

ShaderStruct :: struct {
    name: string,
    fields: []ShaderStructField
}; ShaderStructField :: glsl_type_name_pair


ShaderFunction :: struct {
    return_type: ExtendedGLSLType,
    arguments: []ShaderFunctionArgument,
    label: string,
    source: string,
    is_typed_source: bool,
}; ShaderFunctionArgument :: glsl_type_name_pair

init_shader_function :: proc(ret_type: ExtendedGLSLType, label: string, source: string, is_typed_source: bool, arguments: ..ShaderFunctionArgument) -> (function: ShaderFunction) {
    return { ret_type, arguments, label, source, is_typed_source }
}


ShaderInfo :: struct {
    bindings: [dynamic]ShaderBinding,
    input: [dynamic]ShaderInput,
    output: [dynamic]ShaderOutput,
    uniforms: [dynamic]ShaderUniform,
    structs: [dynamic]ShaderStruct,
    functions: [dynamic]ShaderFunction
}

@(private)
destroy_shader_info :: proc(shader: ^ShaderInfo) {
    delete(shader.bindings)
    delete(shader.input)
    delete(shader.output)
    delete(shader.uniforms)
    delete(shader.structs)
    delete(shader.functions)
}


// Procs to handle shader fields

add_layout :: proc(shader: ^ShaderInfo, layout: ..ShaderBinding) -> (ok: bool) {
    n, err := append_elems(&shader.bindings, ..layout)
    if n != len(layout) || err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to allocate shader layout")
        return
    }

    ok = true
    return
}

add_input :: proc(shader: ^ShaderInfo, input: ..ShaderInput) -> (ok: bool) {
    n, err := append_elems(&shader.input, ..input)
    if n != len(input) || err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to allocate shader input")
        return
    }

    ok = true
    return
}

add_output :: proc(shader: ^ShaderInfo, output: ..ShaderOutput) -> (ok: bool) {
    n, err := append_elems(&shader.output, ..output)
    if n != len(output) || err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to allocate shader output")
        return
    }

    ok = true
    return
}

add_uniforms :: proc(shader: ^ShaderInfo, uniforms: ..ShaderUniform) -> (ok: bool) {
    n, err := append_elems(&shader.uniforms, ..uniforms)
    if n != len(uniforms) || err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to allocate shader uniforms")
        return
    }

    ok = true
    return
}

add_structs :: proc(shader: ^ShaderInfo, structs: ..ShaderStruct) -> (ok: bool) {
    n, err := append_elems(&shader.structs, ..structs)
    if n != len(structs) || err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to allocate shader structs")
        return
    }

    ok = true
    return
}

add_functions :: proc(shader: ^ShaderInfo, functions: ..ShaderFunction) -> (ok: bool) {
    n, err := append_elems(&shader.functions, ..functions)
    if n != len(functions) || err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to allocate shader functions")
        return
    }

    ok = true
    return
}

//

// If more types are added the ShaderReadFlags must be updated for the bit size
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
    source: ShaderSource
}

destroy_shader :: proc(shader: ^Shader) {
    destroy_shader_source(&shader.source)
}


ShaderSource :: struct {
    is_available: bool,
    shader_info: ShaderInfo,
    string_source: string
}

destroy_shader_source :: proc(source: ^ShaderSource) {
    delete(source.string_source)
    destroy_shader_info(&source.shader_info)
}


ShaderIdentifier :: Maybe(u32)

ShaderProgram :: struct {
    id: ShaderIdentifier,
    shaders: [dynamic]Shader,
    uniform_cache: ShaderUniformCache
}


@(private)
init_shader_program:: proc(shader_sources: []Shader) -> (program: ShaderProgram) {
    dbg.debug_point()
    append_elems(&program.shaders, ..shader_sources)
    return
}

destroy_shader_program :: proc(program: ^ShaderProgram) {
    dbg.debug_point()
    for &shader in program.shaders do destroy_shader(&shader)
    delete(program.shaders)
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

/*
    Builds/Deserializes the source as a single string with newlines
    Uses glsl version 430 core
    Todo: Control for versioning
*/
build_shader_source :: proc(shader_info: ShaderInfo, type: ShaderType) -> (shader: Shader, ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Building Shader Source")

    builder, err := strings.builder_make(); if err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogLevel.ERROR, "Allocator error while building shader source")
        return shader, ok
    }


    strings.write_string(&builder, "#version 430 core\n")
    for layout in shader_info.bindings {
        fmt.sbprintfln(&builder, "layout (location = %d) in %s %s;", layout.location, extended_glsl_type_to_string(layout.data_type), layout.name)
    }

    for output in shader_info.output {
        fmt.sbprintfln(&builder, "out %s %s;", extended_glsl_type_to_string(output.type), output.name)
    }

    for input in shader_info.input {
        fmt.sbprintfln(&builder, "in %s %s;", extended_glsl_type_to_string(input.type), input.name)
    }

    for uniform in shader_info.uniforms {
        fmt.sbprintfln(&builder, "uniform %s %s;", extended_glsl_type_to_string(uniform.type), uniform.name)
    }

    for struct_definition in shader_info.structs {
        fmt.sbprintfln(&builder, "struct %s {{", struct_definition.name)
        for field in struct_definition.fields {
            fmt.sbprintfln(&builder, "\t%s %s;", extended_glsl_type_to_string(field.type), field.name)
        }
        fmt.sbprintfln(&builder, "}};")
        strings.write_string(&builder, "\n")
    }

    for function in shader_info.functions {
        strings.write_string(&builder, "\n")
        if function.is_typed_source do strings.write_string(&builder, function.source)
        else {
            fmt.sbprintf(&builder, "%s %s(", extended_glsl_type_to_string(function.return_type), function.label)
            for argument, i in function.arguments {
                fmt.sbprintf(&builder, "%s %s", extended_glsl_type_to_string(argument.type), argument.name)
                if i != len(function.arguments) - 1 do strings.write_string(&builder, ",")
            }
            fmt.sbprintf(&builder, ") {{\n%s\n}}", function.source)
        }
    }


    shader.source = ShaderSource{ true, shader_info, strings.to_string(builder)}
    shader.type = type

    return shader, true
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
            dbg.debug_point(dbg.LogLevel.ERROR, "Unconvertable GLSL type: %v", type)
            return
    }

    ok = true
    return
}


extended_glsl_type_to_string :: proc(type: ExtendedGLSLType, caller_location := #caller_location) -> (result: string) {

    struct_type, struct_ok := type.(ShaderStruct)
    if struct_ok do return struct_type.name

    glsl_type, type_is_glsl := type.(GLSLDataType)
    if type_is_glsl {
        result, type_is_glsl = reflect.enum_name_from_value(glsl_type)
        if !type_is_glsl {
            dbg.debug_point(dbg.LogLevel.ERROR, "GLSL type is not valid")
            return "*INVALID TYPE*"
        }

        return result
    }
    else {
        dbg.debug_point(dbg.LogLevel.ERROR, "GLSL type given as nil")
        return "*INVALID TYPE*"
    }

    return
}

//

// shader gpu control - uniforms, expressing, etc.

express_shader :: proc(program: ^ShaderProgram) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Expressing shader")

    if program.id != nil do return true

    shader_ids := make([dynamic]u32, len(program.shaders))
    defer delete(shader_ids)

    for shader, i in program.shaders {
        dbg.debug_point(dbg.LogLevel.INFO, "Expressing source")
        if !shader.source.is_available {
            dbg.debug_point(dbg.LogLevel.ERROR, "Could not express shader %#v, string source has not yet been built", shader)
            continue
        }

        id, compile_ok := gl.compile_shader_from_source(shader.source.string_source, conv_gl_shader_type(shader.type))
        if !compile_ok {
            dbg.debug_point(dbg.LogLevel.ERROR, "Could not compile shader source: %s", shader.source)
            return ok
        }
        shader_ids[i] = id
    }

    program.id = gl.create_and_link_program(shader_ids[:]) or_return
    ok = true
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

ShaderReadFlags :: bit_field u8 {
    Parse: bool     | 1,
    Express: bool   | 1,
    ShaderLanguage: ShadingLanguage | 3
}

ShaderPath :: struct {
    directory: string,
    filename: string
}

read_shader_source :: proc(flags: ShaderReadFlags, filenames: ..string) -> (program: ShaderProgram, ok: bool) {
    // todo turn init_shader_source into an actual procedure with the same functionality
    _init_shader_source :: proc(source: string, extension: string, flags: ShaderReadFlags) -> (shader: Shader, ok: bool) {
        shader_type := extension_to_shader_type(extension)
        source := ShaderSource{ string_source = strings.clone(source)}
        shader = Shader{ source = source, type = shader_type}

        if flags.Parse {
            shader.source.shader_info = parse_shader_source(shader.source.string_source, flags) or_return
            shader.source.is_available = true
        }

        ok = true
        return
    }

    shader_sources: [dynamic]Shader

    for filename in filenames {
        last_ellipse_location := strings.last_index(filename, ".")
        if last_ellipse_location != -1 && !strings.contains(filename[last_ellipse_location:], "/") {
            // Extension given
            extension := filename[last_ellipse_location:]

            if slice.contains(ACCEPTED_SHADER_EXTENSIONS, extension) {
                source, err := futils.read_file_source(filename); defer delete(source);
                handle_file_read_error(filename, err) or_return

                append(&shader_sources, _init_shader_source(source, extension, flags) or_return)
            }
            else {
                dbg.debug_point(dbg.LogLevel.ERROR, "Shader extension not accepted: %s", extension)
            }
        }
        else {
            // Extension not given
            file_found := false
            for extension in ACCEPTED_SHADER_EXTENSIONS {
                full_path := utils.concat(filename, ".", extension); defer delete(full_path)
                source, err := futils.read_file_source(full_path); defer delete(source)

                if err == .None {
                    dbg.debug_point(dbg.LogLevel.INFO, "Successfully read file. File path: \"%s\"", full_path)
                    append(&shader_sources, _init_shader_source(source, extension, flags) or_return)
                    file_found = true
                }
                else if err == .FileReadError {
                    file_found = true
                    dbg.debug_point(dbg.LogLevel.ERROR, "Error occurred while reading the contents of file. Filename: \"%s\"", full_path)
                }
            }

            if !file_found {
                cwd := os.get_current_directory()
                defer delete(cwd)
                dbg.debug_point(dbg.LogLevel.ERROR, "File could not be found from the current directory. File path: \"%s\", Current directory: \"%s\"", filename, cwd)
            }
        }

    }

    if len(shader_sources) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Failed to read any shader file sources")
    }

    program = init_shader_program(shader_sources[:])
    if flags.Express {
        express_shader(&program)
    }

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
    dbg.debug_point(level, "%s. File path: \"%s\"", message, filepath, loc = loc)

    return
}

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


attach_program :: proc(program: ShaderProgram, loc := #caller_location) {
    if program_id, id_ok := utils.unwrap_maybe(program.id); !id_ok {
        dbg.debug_point(dbg.LogLevel.INFO, "Shader program not yet created")
        return
    }
    else{
        gl.UseProgram(program_id)
    }
}