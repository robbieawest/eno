package resource

import gl "vendor:OpenGL"

import dbg "../debug"

import "core:fmt"
import "core:strings"
import "../utils"

// Defines procedures for working with opengl uniforms

UniformMetaData :: struct {
    type: ExtendedGLSLType,
    location: i32
}

ShaderUniforms :: distinct map[string]UniformMetaData

get_uniform_metadata :: proc(program: ^ShaderProgram, label: string, loc := #caller_location) -> (metadata: UniformMetaData, ok: bool) {
    if label not_in program.uniforms {
        // dbg.log(.WARN, "Program '%s' does not contain the uniform '%s'", program.name, label, loc=loc)
        return
    }

    return program.uniforms[label], true
}

get_uniform_location :: proc(program: ^ShaderProgram, label: string, loc := #caller_location) -> (location: i32, ok: bool) {
    return (get_uniform_metadata(program, label, loc) or_return).location, true
}

set_shader_uniform_metadata :: proc(program: ^ShaderProgram, allocator := context.allocator, loc := #caller_location) -> (ok: bool) {
    if program.id == nil {
        dbg.log(.ERROR, "Program is not yet transferred", loc=loc)
        return
    }
    id := program.id.?

    num_uniforms: i32
    gl.GetProgramiv(id, gl.ACTIVE_UNIFORMS, &num_uniforms)

    max_uniform_name_length: i32
    gl.GetProgramiv(id, gl.ACTIVE_UNIFORM_MAX_LENGTH, &max_uniform_name_length)

    for i in 0..<num_uniforms {
        name_buf := make([]byte, max_uniform_name_length, allocator=allocator); defer delete(name_buf, allocator)
        length_given: i32; arr_size: i32; type: u32
        gl.GetActiveUniform(id, u32(i), max_uniform_name_length, &length_given, &arr_size, &type, raw_data(name_buf))

        name_cstr := cstring(raw_data(name_buf[:length_given]))
        name := strings.clone_from_cstring(name_cstr, allocator=allocator, loc=loc)


        name_split, alloc_err := strings.split(name, "[", allocator); defer delete(name_split)

        if alloc_err != .None || len(name_split) == 0 {
            dbg.log(.ERROR, "Error while splitting fixed array name")
            return
        }
        base_name := name_split[0]

        metadata: UniformMetaData
        metadata.location = gl.GetUniformLocation(id, name_cstr)
        metadata.type = conv_gl_glsl_type(type, arr_size) or_return

        #partial switch m_type in metadata.type {
            case GLSLFixedArray:

                for i in 0..<m_type.size {
                    elem_name := fmt.caprintf("%s[%d]", base_name, i, allocator=allocator)
                    elem_metadata := metadata
                    elem_metadata.location = gl.GetUniformLocation(id, elem_name)
                    elem_metadata.type = m_type.type

                    program.uniforms[string(elem_name)] = elem_metadata
                }
        }

        program.uniforms[base_name] = metadata
    }

    return true
}

// ** Setting uniform values **

set_uniform :: proc{
    Uniform1f, Uniform2f, Uniform3f, Uniform4f,
    Uniform1i, Uniform2i, Uniform3i, Uniform4i,
    Uniform1ui, Uniform2ui, Uniform3ui, Uniform4ui,
    set_vector_uniform, set_matrix_uniform
}

Uniform1f :: proc(program: ^ShaderProgram, label: string, v0: f32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform1f(location, v0)
}

Uniform1d :: proc(program: ^ShaderProgram, label: string, v0: f64) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform1d(location, v0)
}

Uniform1i :: proc(program: ^ShaderProgram, label: string, v0: i32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform1i(location, v0)
}

Uniform1ui :: proc(program: ^ShaderProgram, label: string, v0: u32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform1ui(location, v0)
}

Uniform2f :: proc(program: ^ShaderProgram, label: string, v0: f32, v1: f32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform2f(location, v0, v1)
}

Uniform2d :: proc(program: ^ShaderProgram, label: string, v0: f64, v1: f64) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform2d(location, v0, v1)
}

Uniform2i :: proc(program: ^ShaderProgram, label: string, v0: i32, v1: i32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform2i(location, v0, v1)
}

Uniform2ui :: proc(program: ^ShaderProgram, label: string, v0: u32, v1: u32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform2ui(location, v0, v1)
}

Uniform3f :: proc(program: ^ShaderProgram, label: string, v0: f32, v1: f32, v2: f32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform3f(location, v0, v1, v2)
}

Uniform3d :: proc(program: ^ShaderProgram, label: string, v0: f64, v1: f64, v2: f64) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform3d(location, v0, v1, v2)
}

Uniform3i :: proc(program: ^ShaderProgram, label: string, v0: i32, v1: i32, v2: i32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform3i(location, v0, v1, v2)
}

Uniform3ui :: proc(program: ^ShaderProgram, label: string, v0: u32, v1: u32, v2: u32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform3ui(location, v0, v1, v2)
}

Uniform4f :: proc(program: ^ShaderProgram, label: string, v0: f32, v1: f32, v2: f32, v3: f32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform4f(location, v0, v1, v2, v3)
}

Uniform4d :: proc(program: ^ShaderProgram, label: string, v0: f64, v1: f64, v2: f64, v3: f64) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform4d(location, v0, v1, v2, v3)
}

Uniform4i :: proc(program: ^ShaderProgram, label: string, v0: i32, v1: i32, v2: i32, v3: i32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform4i(location, v0, v1, v2, v3)
}

Uniform4ui :: proc(program: ^ShaderProgram, label: string, v0: u32, v1: u32, v2: u32, v3: u32) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    gl.Uniform4ui(location, v0, v1, v2, v3)
}


set_vector_uniform :: proc(
    program: ^ShaderProgram,
    label: string,
    count: i32,
    args: ..$T
) -> (ok: bool)
    where  T == i32 || T == u32 || T == f32 || T == f64
{

    n_args := i32(len(args))
    if n_args % count != 0 {
        dbg.log(.ERROR, "Number of args must be divisible by count")
        return
    }

    invalid :: proc() -> bool { dbg.log(.ERROR, "Invalid count in array"); return false }
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return

    when T == u32 {
        switch n_args / count {
            case 1: gl.Uniform1uiv(location, count, raw_data(args))
            case 2: gl.Uniform2uiv(location, count, raw_data(args))
            case 3: gl.Uniform3uiv(location, count, raw_data(args))
            case 4: gl.Uniform4uiv(location, count, raw_data(args))
            case :
                return invalid()
        }
    }
    else when T == i32 {
        switch n_args / count {
            case 1: gl.Uniform1iv(location, count, raw_data(args))
            case 2: gl.Uniform2iv(location, count, raw_data(args))
            case 3: gl.Uniform3iv(location, count, raw_data(args))
            case 4: gl.Uniform4iv(location, count, raw_data(args))
            case :
                return invalid()
        }
    }
    else when T ==  f32 {
        switch n_args / count {
            case 1: gl.Uniform1fv(location, count, raw_data(args))
            case 2: gl.Uniform2fv(location, count, raw_data(args))
            case 3: gl.Uniform3fv(location, count, raw_data(args))
            case 4: gl.Uniform4fv(location, count, raw_data(args))
            case :
                return invalid()
        }
    }
    else when T == f64 {
        switch n_args / count {
            case 1: gl.Uniform1dv(location, count, raw_data(args))
            case 2: gl.Uniform2dv(location, count, raw_data(args))
            case 3: gl.Uniform3dv(location, count, raw_data(args))
            case 4: gl.Uniform4dv(location, count, raw_data(args))
            case :
                return invalid()
        }
    }

    ok = true
    return
}


set_matrix_uniform :: proc(
    program: ^ShaderProgram,
    label: string,
    mat: matrix[$N, $M]$T,
    count: i32 = 1,
    transpose: bool = false,
)
    where T == f32 || T == f64 && N > 1 && N <= 4 && M > 1 && M <= 4
{
    mat := mat
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return

    switch 4 * N + M {
        case 10:
            // Switch should be possible but no! matrix $T parapoly bug?
            if T == f32 do gl.UniformMatrix2fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix2dv(location, count, transpose, cast([^]f64)&mat[0, 0])  // This cast should not be needed but the compiler wants it - thinks mat[0, 0] is f32
        case 14:
            if T == f32 do gl.UniformMatrix3x2fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix3x2dv(location, count, transpose, cast([^]f64)&mat[0, 0])
        case 18:
            if T == f32 do gl.UniformMatrix4x2fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix4x2dv(location, count, transpose, cast([^]f64)&mat[0, 0])
        case 11:
            if T == f32 do gl.UniformMatrix2x3fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix2x3dv(location, count, transpose, cast([^]f64)&mat[0, 0])
        case 15:
            if T == f32 do gl.UniformMatrix3fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix3dv(location, count, transpose, cast([^]f64)&mat[0, 0])
        case 19:
            if T == f32 do gl.UniformMatrix4x3fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix4x3dv(location, count, transpose, cast([^]f64)&mat[0, 0])
        case 12:
            if T == f32 do gl.UniformMatrix2x4fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix2x4dv(location, count, transpose, cast([^]f64)&mat[0, 0])
        case 16:
            if T == f32 do gl.UniformMatrix3x4fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix3x4dv(location, count, transpose, cast([^]f64)&mat[0, 0])
        case 20:
            if T == f32 do gl.UniformMatrix4fv(location, count, transpose, &mat[0, 0])
            else do gl.UniformMatrix4dv(location, count, transpose, cast([^]f64)&mat[0, 0])
    }
}

get_uniform_type_from_glsl_type :: proc(type: GLSLType) -> (ret: typeid) {
    switch type {
        case .uint: ret = u32
        case .float: ret = f32
        case .vec2: ret = [2]f32
        case .vec3: ret =  [3]f32
        case .vec4: ret = [4]f32
        // ..todo
        case: dbg.log(.WARN, "GLSL type %v not yet supported", type)
    }
    return
}