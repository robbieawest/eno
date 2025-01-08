package gpu

import gl "vendor:OpenGL"

import dbg "../debug"

import "core:strings"
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

//
set_uniform :: proc{
    gl.Uniform1f, gl.Uniform2f, gl.Uniform3f, gl.Uniform4f,
    gl.Uniform1i, gl.Uniform2i, gl.Uniform3i, gl.Uniform4i,
    gl.Uniform1ui, gl.Uniform2ui, gl.Uniform3ui, gl.Uniform4ui,
    set_vector_uniform, set_vector_uniform_given_location,
    set_matrix_uniform, set_matrix_uniform_given_location
}


UniformVectorProc :: struct($backing_type: typeid) {
   procedure: proc(location: i32, count: i32, vector: [^]backing_type)
}

set_vector_uniform :: proc(program: ^ShaderProgram, label: string, vector: [$N]$T, gl_proc: UniformVectorProc(T)) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    set_vector_uniform_given_location(location, vector, gl_proc)
}

set_vector_uniform_given_location :: proc(location: UniformLocation, vector: [$N]$T, gl_proc: UniformVectorProc(T)) {
    gl_proc(location, N, raw_data(vector))
}


UniformMatrixProc :: struct($backing_type: typeid) {
    procedure: proc(location: i32, count: i32, transpose: bool, mat: [^]backing_type)
}
set_matrix_uniform :: proc(program: ^ShaderProgram, label: string, transpose: bool, mat: [$N]$T, gl_proc: UniformMatrixProc(T)) {
    location, uniform_found := get_uniform_location(program, label); if !uniform_found do return
    set_matrix_uniform_given_location(location, transpose, mat, gl_proc)
}

set_matrix_uniform_given_location :: proc(location: UniformLocation, transpose: bool, mat: [$N]$T, gl_proc: UniformMatrixProc(T)) {
    gl_proc(location, N, transpose, raw_data(vector))
}

//