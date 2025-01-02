package gpu

import dbg "../debug"

import "core:testing"
import "core:log"
import "core:fmt"

/*
@(init)
debug_setup :: proc() {
    dbg.init_debug_stack()
}


@(test)
shader_creation_test :: proc(t: ^testing.T) {

    shader: Shader
    add_layout(&shader,
        { 0, .vec3, "a_position"},
        { 1, .vec4, "a_colour"}
    )

    add_output(&shader, { .vec4, "v_colour"})
    add_uniforms(&shader, { .mat4, "u_transform"})
    add_functions(&shader,
        {
            .void,
            []ShaderFunctionArgument {},
            "main",
            `    gl_Position = u_transform * vec4(a_position, 1.0);
    v_colour = a_colour;`,
            false
        }
    )
    defer destroy_shader(&shader)

    log.infof("shader out: %#v", shader)
}

@(test)
build_shader_source_test :: proc(t: ^testing.T) {
    shader: Shader
    add_layout(&shader,
        { 0, .vec3, "a_position"},
        { 1, .vec4, "a_colour"}
    )

    add_output(&shader, { .vec4, "v_colour"})
    add_uniforms(&shader, { .mat4, "u_transform"})
    add_functions(&shader,
        {
            .void,
            []ShaderFunctionArgument {},
            "main",
            `    gl_Position = u_transform * vec4(a_position, 1.0);
    v_colour = a_colour;`,
            false
        }
    )

    shader_source, ok := build_shader_source(shader, .VERTEX)
    defer destroy_shader_source(&shader_source)

    testing.expect(t, ok, "ok check")
    log.infof("shader source out: %#v", shader_source)

    log.info(shader_source.source)
}
*/

@(test)
shader_read_test :: proc(t: ^testing.T) {
    program, ok := read_shader_source({ Express = true, ShaderLanguage = .GLSL }, "demo_shader")

    testing.expect(t, ok, "ok check")
    testing.expect(t, program.id != -1)
    log.infof("%#v", program)
}