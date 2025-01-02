package gpu

import "core:strings"
import "base:intrinsics"

// Implements parsing for GLSL shaders
// This allows a shader file source to be represented as a Shader in the engine, and for programmers to add/modify the shader dynamically
// WIP

parse_shader_source :: proc(source: string, flags: ShaderReadFlags) -> (shader: Shader, ok: bool) {
/*
    Parsing shader source:
        - get lines
        - tokenize lines (one pass)
        - identify shader components via tokens per line (one pass)

    Token: string
*/

    lines: []string = strings.split_lines(source)
    defer delete(lines)

    #partial switch flags.ShaderLanguage {
    case .GLSL: {
        tokens := tokenize_shader_source(lines, GLSLTokenType)
        defer {
            for token_line in tokens do delete(token_line)
            delete(tokens)
        }
    }
    }



    return
}



@(private = "file")
GLSLTokenType :: enum {
    Keyword,
    // ...
}

@(private = "file")
Token :: struct($TokenType: typeid)
    where intrinsics.type_is_enum(TokenType)
{
    type: TokenType,
    value: string
}

@(private = "file")
tokenize_shader_source :: proc(lines: []string, $TokenType: typeid) -> (tokens: [dynamic][]Token(TokenType)) {
    tokens = make([dynamic][]Token(TokenType), 0, len(lines))

    for i := 0; i < len(lines); i += 1 {
        line := strings.trim_space(lines[i])
        if len(line) == 0 do break

        //append(&tokens, strings.split(line, " "))
    }

    return
}