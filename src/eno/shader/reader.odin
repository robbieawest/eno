package shader

import "../utils"

import "core:strings"

/*
    Implementations for shader file reading and parsing
    A shader source does not need to have a valid serialized Shader instance attached to it, it can be a single whole source as well.
*/

ShaderReadFlags :: bit_field u8 {
    Express: bool       | 1,
    Parse: bool         | 1,
    Type: ShaderType    | 3
}

read_shader_source :: proc(filename: string, flags: ShaderReadFlags) -> (program: ShaderProgram, ok: bool) {
    shader_source: string
    if strings.contains(filename, ".") {
        shader_source = utils.read_file_source(filename) or_return
    }

    // todo implement


    ok = true
    return
}

