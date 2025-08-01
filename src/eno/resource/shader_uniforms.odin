package resource

import gl "vendor:OpenGL"

import dbg "../debug"

import "core:strings"
import "../utils"

// Defines procedures for working with opengl uniforms

@(private)
UniformLocation :: i32

ShaderUniformCache :: distinct map[string]UniformLocation

@(private)
cache_checked_uniform_get :: proc(program: ^ShaderProgram, label: string) -> (location: UniformLocation, ok: bool) {
    return program.uniform_cache[label]
}


get_uniform_location :: proc(program: ^ShaderProgram, label: string) -> (location: i32 , ok: bool) {
    dbg.log()
    if program.id == nil {
        dbg.log(.ERROR, "Could not get uniform, program is not yet expressed")
        return
    }

    if cached_location, uniform_is_cached := cache_checked_uniform_get(program, label); uniform_is_cached {
        return cached_location, uniform_is_cached
    }

    // Not found in cache
    location, ok = get_uniform_location_without_cache(program, label)
    if !ok {
        // dbg.debug_point(.ERROR, "Could not get uniform location \"%s\"", label)
        return
    }

    cache_uniform(program, label, location)

    return
}


get_uniform_location_without_cache :: proc(program: ^ShaderProgram, label: string) -> (location: UniformLocation, ok: bool) {

    if program.id == nil {
        dbg.log(.ERROR, "Shader program not yet created")
        return
    }

    location = gl.GetUniformLocation(utils.unwrap_maybe(program.id) or_return, strings.clone_to_cstring(label))
    if location == -1 {
        return
    }

    ok = true
    return
}


register_uniform :: proc(program: ^ShaderProgram, label: string) -> (ok: bool) {

    if _, uniform_is_cached := cache_checked_uniform_get(program, label); uniform_is_cached {
        dbg.log(.ERROR, "Uniform \"%s\" already exists")
        return
    }

    location: UniformLocation; location, ok = get_uniform_location_without_cache(program, label)
    if !ok {
        dbg.log(.ERROR, "Could not get uniform location \"%s\"", label)
        return
    }

    cache_uniform(program, label, location)

    ok = true
    return
}

@(private)
cache_uniform :: proc(program: ^ShaderProgram, label: string, location: UniformLocation) {
    program.uniform_cache[label] = location
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
    if len(args) % count != 0 {
        dbg.log(.ERROR, "Number of args must be divisible by count")
        return
    }

    invalid :: proc() -> bool { dbg.log(.ERROR, "Combination of args and count is invalid. num_args: %d, count: %d", len(args), count); return }

    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    switch T {
    case u32:
        switch len(args) / count {
            case 1: gl.Uniform1uiv(location, count, raw_data(args))
            case 2: gl.Uniform2uiv(location, count, raw_data(args))
            case 3: gl.Uniform3uiv(location, count, raw_data(args))
            case 4: gl.Uniform4uiv(location, count, raw_data(args))
            case :
                return invalid()
        }
    case i32:
        switch len(args) / count {
            case 1: gl.Uniform1iv(location, count, raw_data(args))
            case 2: gl.Uniform2iv(location, count, raw_data(args))
            case 3: gl.Uniform3iv(location, count, raw_data(args))
            case 4: gl.Uniform4iv(location, count, raw_data(args))
            case :
                return invalid()
        }
    case f32:
        switch len(args) / count {
            case 1: gl.Uniform1fv(location, count, raw_data(args))
            case 2: gl.Uniform2fv(location, count, raw_data(args))
            case 3: gl.Uniform3fv(location, count, raw_data(args))
            case 4: gl.Uniform4fv(location, count, raw_data(args))
            case :
                return invalid()
        }
    case f64:
        switch len(args) / count {
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


//