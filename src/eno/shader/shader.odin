package shader

import gl "vendor:OpenGL"
import SDL "vendor:sdl2"

import dbg "../debug"

import "core:strings"
import "core:mem"
import "core:log"
import "core:fmt"
import "core:testing"

// Defines a generalized shader structure which then compiles using the given render API

ExtendedGLSLType :: union {
    ^ShaderStruct,
    GLSLDataType
}


glsl_type_name_pair :: struct{
    type: ExtendedGLSLType,
    name: string
}


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
    sources: []^ShaderSource,
    expressed: bool
}

init_shader_program :: proc(shader_sources: []^ShaderSource) -> (program: ^ShaderProgram){
    dbg.debug_point()
    program = new(ShaderProgram)
    program.sources = shader_sources
    return program
}

destroy_shader_program :: proc(program: ^ShaderProgram) {
    dbg.debug_point()
    for &source in program.sources do destroy_shader_source(source)
    free(program)
}

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