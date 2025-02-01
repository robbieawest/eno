package gpu

import gl "vendor:OpenGL"

import dbg "../debug"

import "core:strings"
import "core:reflect"
import glm "core:math/linalg/glsl"

// Defines procedures for working with uniforms

@(private)
UniformLocation :: i32

ShaderUniformCache :: distinct map[string]UniformLocation

@(private)
cache_checked_uniform_get :: proc(program: ^ShaderProgram, label: string) -> (location: UniformLocation, ok: bool) {
    return program.uniform_cache[label]
}


get_uniform_location :: proc(program: ^ShaderProgram, label: string) -> (location: i32 , ok: bool) {
    dbg.debug_point()
    if !program.expressed {
        dbg.debug_point(dbg.LogLevel.ERROR, "Could not get uniform, program is not yet expressed")
        return
    }

    if cached_location, uniform_is_cached := cache_checked_uniform_get(program, label); uniform_is_cached {
        return cached_location, uniform_is_cached
    }

    // Not found in cache
    location, ok = get_uniform_location_without_cache(program, label)
    if !ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "Could not get uniform location \"%s\"", label)
        return
    }

    cache_uniform(program, label, location)

    return
}


get_uniform_location_without_cache :: proc(program: ^ShaderProgram, label: string) -> (location: UniformLocation, ok: bool) {

    program_id := program.id.(i32)
    if program_id == -1 {
        return
    }


    location = gl.GetUniformLocation(u32(program_id), strings.clone_to_cstring(label))
    if location == -1 {
        return
    }

    ok = true
    return
}


register_uniform :: proc(program: ^ShaderProgram, label: string) -> (ok: bool) {

    if _, uniform_is_cached := cache_checked_uniform_get(program, label); uniform_is_cached {
        dbg.debug_point(dbg.LogLevel.ERROR, "Uniform \"%s\" already exists")
        return
    }

    location: UniformLocation; location, ok = get_uniform_location_without_cache(program, label)
    if !ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "Could not get uniform location \"%s\"", label)
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



UniformVectorProc :: struct($backing_type: typeid) {
   procedure: proc(location: i32, count: i32, vector: [^]backing_type)
}

set_vector_uniform :: proc(
    program: ^ShaderProgram,
    label: string,
    count: i32,
    args: ..$T
) -> (ok: bool) {
    if len(args) % count != 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Number of args must be divisible by count")
        return
    }

    invalid :: proc() -> bool { dbg.debug_point(dbg.LogLevel.ERROR, "Combination of args and count is invalid. num_args: %d, count: %d", len(args), count); return }

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
    case:
        dbg.debug_point(dbg.LogLevel.ERROR, "Type not accepted: %v", T)
        return
    }

    ok = true
    return
}


set_matrix_uniform :: proc(
    program: ^ShaderProgram,
    label: string, transpose: bool,
    mat: matrix[$N,$M]$T
) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    //todo
}


//