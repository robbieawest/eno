package shader

import gl "vendor:OpenGL"

import gpu "../gpu"

import "core:strings"
import "core:mem"
import "core:log"
import "core:fmt"
import "core:testing"

// Defines a generalized shader structure which then compiles using the given render API

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

ExtendedGLSLType :: union {
    ^ShaderStruct,
    GLSLDataType
}

GLSL_type_to_string :: proc(type: GLSLDataType) -> (result: string) {
    switch (type) {
    case .void: result = "void"
    case .int: result = "int"
    case .uint: result = "uint"
    case .float: result = "float"
    case .double: result = "double"
    case .bool: result = "bool"
    case .vec2: result = "vec2"
    case .vec3: result = "vec3"
    case .vec4: result = "vec4"
    case .bvec2: result = "bvec2"
    case .bvec3: result = "bvec3"
    case .bvec4: result = "bvec4"
    case .ivec2: result = "ivec2"
    case .ivec3: result = "ivec3"
    case .ivec4: result = "ivec4"
    case .mat2: result = "mat2"
    case .mat3: result = "mat3"
    case .mat4: result = "mat4"
    case .mat2x2: result = "mat2x2"
    case .mat2x3: result = "mat2x3"
    case .mat2x4: result = "mat2x4"
    case .mat3x2: result = "mat3x2"
    case .mat3x3: result = "mat3x3"
    case .mat3x4: result = "mat3x4"
    case .mat4x2: result = "mat4x2"
    case .mat4x3: result = "mat4x3"
    case .mat4x4: result = "mat4x4"
    case .dmat2: result = "dmat2"
    case .dmat3: result = "dmat3"
    case .dmat4: result = "dmat4"
    case .dmat2x2: result = "dmat2x2"
    case .dmat2x3: result = "dmat2x3"
    case .dmat2x4: result = "dmat2x4"
    case .dmat3x2: result = "dmat3x2"
    case .dmat3x3: result = "dmat3x3"
    case .dmat3x4: result = "dmat3x4"
    case .dmat4x2: result = "dmat4x2"
    case .dmat4x3: result = "dmat4x3"
    case .dmat4x4: result = "dmat4x4"
    case .sampler1D: result = "sampler1D"
    case .sampler2D: result = "sampler2D"
    case .sampler3D: result = "sampler3D"
    case .samplerCube: result = "samplerCube"
    case .sampler2DShadow: result = "sampler2DShadow"
    }
    return result
}


extended_glsl_type_to_string :: proc(type: ExtendedGLSLType, caller_location := #caller_location) -> (result: string) {
    // *Returns labels of structs

    struct_type, struct_ok := type.(^ShaderStruct)
    if struct_ok do return struct_type.name

    glsl_type, glsl_ok := type.(GLSLDataType)
    if glsl_ok do return GLSL_type_to_string(glsl_type)
    else do log.errorf("Invalid ExtendedGLSLType union is nil : loc: %s", caller_location)

    return result
}


glsl_type_name_pair :: struct{ type: ExtendedGLSLType, name: string }


ShaderLayout :: struct {
    location: uint,
    type: ExtendedGLSLType,
    name: string
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

Shader :: struct {
    layout: [dynamic]ShaderLayout,
    input: [dynamic]ShaderInput,
    output: [dynamic]ShaderOutput,
    uniforms: [dynamic]ShaderUniform,
    structs: [dynamic]ShaderStruct,
    functions: [dynamic]ShaderFunction
}

destroy_shader :: proc(shader: ^Shader) {
    delete(shader.layout)
    delete(shader.input)
    delete(shader.output)
    delete(shader.uniforms)
    delete(shader.structs)
    delete(shader.functions)
    free(shader)
}


// Procs to handle shader fields

init_shader :: proc { _init_shader_empty, _init_shader_with_layout }

@(private)
_init_shader_empty :: proc() -> (shader: ^Shader) {
    shader = new(Shader)
    return shader
}


@(private)
_init_shader_with_layout :: proc(layout: []ShaderLayout) -> (shader: ^Shader) {
    shader = new(Shader)
    append_elems(&shader.layout, ..layout)
    return shader
}


add_layout :: proc(shader: ^Shader, layout: []ShaderLayout) -> ^Shader {
    append_elems(&shader.layout, ..layout)
    return shader
}

add_input :: proc(shader: ^Shader, input: []ShaderInput) -> ^Shader {
    append_elems(&shader.input, ..input)
    return shader
}

add_output :: proc(shader: ^Shader, output: []ShaderOutput) -> ^Shader {
    append_elems(&shader.output, ..output)
    return shader
}

add_uniforms :: proc(shader: ^Shader, uniforms: []ShaderUniform) -> ^Shader {
    append_elems(&shader.uniforms, ..uniforms)
    return shader
}

add_structs :: proc(shader: ^Shader, structs: []ShaderStruct) -> ^Shader {
    append_elems(&shader.structs, ..structs)
    return shader
}

add_functions :: proc(shader: ^Shader, functions: []ShaderFunction) -> ^Shader {
    append_elems(&shader.functions, ..functions)
    return shader
}

//


// Builds the source as a single string with newlines
// Uses glsl version 440 core
build_shader_source :: proc(shader: ^Shader, type: ShaderType) -> (source: ^ShaderSource, ok: bool) {
    builder, _alloc_err := strings.builder_make(); if _alloc_err != mem.Allocator_Error.None {
        log.error("Allocator error while building shader source")
        return source, ok
    }
    defer strings.builder_destroy(&builder)

    // Todo replace write_string with checked version with a write_stringln alternative
    strings.write_string(&builder, "#version 440 core\n")
    for layout in shader.layout {
        strings.write_string(&builder, "layout (location = ")
        strings.write_uint(&builder, layout.location)
        strings.write_string(&builder, ") in ")
        strings.write_string(&builder, extended_glsl_type_to_string(layout.type))
        strings.write_string(&builder, " ")
        strings.write_string(&builder, layout.name)
        strings.write_string(&builder, "\n")
    }

    for output in shader.output {
        strings.write_string(&builder, "out ")
        strings.write_string(&builder, extended_glsl_type_to_string(output.type))
        strings.write_string(&builder, " ")
        strings.write_string(&builder, output.name)
        strings.write_string(&builder, "\n")
    }

    for input in shader.input {
        strings.write_string(&builder, "out ")
        strings.write_string(&builder, extended_glsl_type_to_string(input.type))
        strings.write_string(&builder, " ")
        strings.write_string(&builder, input.name)
        strings.write_string(&builder, "\n")
    }

    for uniform in shader.uniforms {
        strings.write_string(&builder, "out ")
        strings.write_string(&builder, extended_glsl_type_to_string(uniform.type))
        strings.write_string(&builder, " ")
        strings.write_string(&builder, uniform.name)
        strings.write_string(&builder, "\n")
    }

    for struct_definition in shader.structs {
        strings.write_string(&builder, "struct ")
        strings.write_string(&builder, struct_definition.name)
        strings.write_string(&builder, " {\n")
        for field in struct_definition.fields {
            strings.write_string(&builder, "\t")
            strings.write_string(&builder, extended_glsl_type_to_string(field.type))
            strings.write_string(&builder, " ")
            strings.write_string(&builder, field.name)
            strings.write_string(&builder, ";\n")
        }
        strings.write_string(&builder, "};\n")
    }
    
    for function in shader.functions {
        strings.write_string(&builder, "\n")
        if function.is_typed_source do strings.write_string(&builder, function.source)
        else {
            strings.write_string(&builder, extended_glsl_type_to_string(function.return_type))
            strings.write_string(&builder, " ")
            strings.write_string(&builder, function.label)
            strings.write_string(&builder, "(")

            for argument, i in function.arguments {
                strings.write_string(&builder, extended_glsl_type_to_string(argument.type))
                strings.write_string(&builder, " ")
                strings.write_string(&builder, argument.name)
                if i != len(function.arguments) - 1 do strings.write_string(&builder, ",")
            }
            
            strings.write_string(&builder, ") {\n")
            strings.write_string(&builder, function.source)
            strings.write_string(&builder, "\n")
            strings.write_string(&builder, "}")
        }
        strings.write_string(&builder, "\n")
    }

    source = new(ShaderSource)
    source.compiled_source = strings.to_string(builder)
    source.type = type
    source.shader = shader

    return source, true
}


ShaderSource :: struct {
    type: ShaderType,
    compiled_source: string,
    shader: ^Shader
}

destroy_shader_source :: proc(source: ^ShaderSource) {
    destroy_shader(source.shader)
    free(source)
}



ShaderIdentifier :: union {
    u32,
    //VkShaderModule or a pipeline
}


ShaderProgram :: struct {
    id: ShaderIdentifier,
    sources: []ShaderSource,
    expressed: bool
}

destroy_shader_program :: proc(program: ^ShaderProgram) {
    for &source in program.sources do destroy_shader_source(&source)
    free(program)
}


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


express_shader :: proc(program: ^ShaderProgram) -> (ok: bool) {
    if program.expressed do return true

    switch (gpu.RENDER_API) {
    case .OPENGL:
        shader_ids := make([dynamic]u32, len(program.sources))
        for shader_source in program.sources {
            id, comp_ok := gl.compile_shader_from_source(shader_source.compiled_source, cast(gl.Shader_Type)cast(int) shader_source.type)
            if !comp_ok {
                log.error("Could not express shader source")
                return ok
            }

            append(&shader_ids, id)
        }

        program.id, ok = gl.create_and_link_program(shader_ids[:]); if !ok {
            log.error("Error while creating and linking shader program")
            return ok
        }
        program.expressed = true
    case .VULKAN:
        gpu.vulkan_not_supported()
        return ok
    }
    return true
}



@(test)
shader_creation_test :: proc(t: ^testing.T) {

    shader: ^Shader = init_shader(
                []ShaderLayout {
                    { 0, .vec3, "a_position"},
                    { 1, .vec4, "a_colour"}
                }
        )
    add_output(shader, []ShaderInput {
        { .vec4, "v_colour"}
    })
    add_uniforms(shader, []ShaderUniform {
        { .mat4, "u_transform"}
    })
    add_functions(shader, []ShaderFunction {
        { 
            .void,
            []ShaderFunctionArgument {},
            "main",
            `    gl_Position = u_transform * vec4(a_position, 1.0);
    v_colour = a_colour;`,
            false
        }
    })
    defer destroy_shader(shader)

    log.infof("shader out: %#v", shader)
}

@(test)
build_shader_source_test :: proc(t: ^testing.T) {
    
    shader: ^Shader = init_shader(
                []ShaderLayout {
                    { 0, .vec3, "a_position"},
                    { 1, .vec4, "a_colour"}
                }
        )
    add_output(shader, []ShaderInput {
        { .vec4, "v_colour"}
    })
    add_uniforms(shader, []ShaderUniform {
        { .mat4, "u_transform"}
    })
    add_functions(shader, []ShaderFunction {
        { 
            .void,
            []ShaderFunctionArgument {},
            "main",
            `    gl_Position = u_transform * vec4(a_position, 1.0);
    v_colour = a_colour;`,
            false
        }
    })

    shader_source, ok := build_shader_source(shader, .VERTEX)
    defer destroy_shader_source(shader_source)

    testing.expect(t, ok, "ok check")
    log.infof("shader source out: %#v", shader_source)

    log.info(shader_source.compiled_source)
}
