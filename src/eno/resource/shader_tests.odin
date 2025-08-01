package resource

import dbg "../debug"

import "core:testing"
import "core:log"
import "core:fmt"


@(test)
shader_creation_test :: proc(t: ^testing.T) {

    shader: ShaderInfo; defer destroy_shader_info(shader)

    add_inputs(&shader,
        { .vec3, "a_position" },
        { .vec4, "a_colour" },
    )
    add_outputs(&shader, { .vec4, "v_colour" })

    add_uniforms(&shader, { .mat4, "u_transform"})

    main_func := make_shader_function(.void, "main",
        []string {
            "gl_Position = u_transform * vec4(a_position, 1.0);",
            "v_colour = a_colour"
        }
    )
    add_functions(&shader, main_func)


    log.infof("shader out: %#v", shader)
}

@(test)
build_shader_source_test :: proc(t: ^testing.T) {
    shader: ShaderInfo
    add_inputs(&shader,
    { .vec3, "a_position" },
    { .vec4, "a_colour" },
    )
    add_outputs(&shader, { .vec4, "v_colour" })

    add_uniforms(&shader, { .mat4, "u_transform"})

    main_func := make_shader_function(.void, "main",
    []string {
        "gl_Position = u_transform * vec4(a_position, 1.0);",
        "v_colour = a_colour"
    }
    )
    add_functions(&shader, main_func)


    shader_source, ok := build_shader_from_source(shader, .VERTEX)
    defer destroy_shader(shader_source)

    testing.expect(t, ok, "ok check")
    log.infof("shader source out: %#v", shader_source)

    log.info(shader_source.source.string_source)
}


@(test)
shader_read_test :: proc(t: ^testing.T) {
    shader, ok := read_single_shader_source("resources/shaders/demo_shader.frag", .FRAGMENT)
    defer destroy_shader(shader)

    testing.expect(t, ok, "ok check")
}