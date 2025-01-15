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
    dbg.debug_point(dbg.LogLevel.INFO, "Getting uniform: %s", label)
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
    set_vector_uniform, set_vector_uniform_given_location,
    set_matrix_uniform, set_matrix_uniform_given_location
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
    vector: [$N]$T,
    gl_proc: UniformVectorProc(T)
) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    set_vector_uniform_given_location(location, vector, gl_proc)
}

set_vector_uniform_given_location :: proc(
    location: UniformLocation,
    vector: [$N]$T,
    gl_proc: UniformVectorProc(T)
) {
    gl_proc(location, N, raw_data(vector))
}


UniformMatrixProc :: struct($backing_type: typeid) {
    procedure: proc(location: i32, count: i32, transpose: bool, mat: [^]backing_type)
}

set_matrix_uniform :: proc(
    program: ^ShaderProgram,
    label: string, transpose: bool,
    mat: [$N]$T,
    gl_proc: UniformMatrixProc(T)
) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    set_matrix_uniform_given_location(location, transpose, mat, gl_proc)
}

set_matrix_uniform_given_location :: proc(
    location: UniformLocation,
    transpose: bool,
    mat: [$N]$T,
    gl_proc: UniformMatrixProc(T)
) {
    gl_proc(location, N, transpose, raw_data(vector))
}

//