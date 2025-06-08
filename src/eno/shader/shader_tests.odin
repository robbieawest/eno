package gpu

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


    shader_source, ok := build_shader_source(shader, .VERTEX)
    defer destroy_shader(shader_source)

    testing.expect(t, ok, "ok check")
    log.infof("shader source out: %#v", shader_source)

    log.info(shader_source.source.string_source)
}


@(test)
shader_read_test :: proc(t: ^testing.T) {
    program, ok := read_shader_source({ ShaderLanguage = .GLSL }, "resources/shaders/demo_shader")
    defer destroy_shader_program(program)

    testing.expect(t, ok, "ok check")
    nil_maybe: Maybe(u32)
    testing.expect_value(t, nil_maybe, program.id)
    log.infof("%#v", program)
    if len(program.shaders) == 2 {
        log.infof("%s, %s", program.shaders[0].type, program.shaders[0].source)
        log.infof("%s, %s", program.shaders[1].type, program.shaders[1].source)
    }
}