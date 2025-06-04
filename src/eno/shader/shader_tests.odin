package gpu

import dbg "../debug"

import "core:testing"
import "core:log"
import "core:fmt"


@(test)
shader_creation_test :: proc(t: ^testing.T) {

    shader: ShaderInfo
    add_layouts_of_type(&shader, .INPUT,
        { .vec3, "a_position" },
        { .vec4, "a_colour" },
    )
    add_layouts_of_type(&shader, .OUTPUT, { .vec4, "v_colour" })

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
    defer destroy_shader_info(shader)

    log.infof("shader out: %#v", shader)
}

@(test)
build_shader_source_test :: proc(t: ^testing.T) {
    shader: ShaderInfo
    add_layouts_of_type(&shader, .INPUT,
    { .vec3, "a_position" },
    { .vec4, "a_colour" },
    )
    add_layouts_of_type(&shader, .OUTPUT, { .vec4, "v_colour" })


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
    defer destroy_shader(&shader_source)

    testing.expect(t, ok, "ok check")
    log.infof("shader source out: %#v", shader_source)

    log.info(shader_source.source)
}


@(test)
shader_read_test :: proc(t: ^testing.T) {
    program, ok := read_shader_source({ ShaderLanguage = .GLSL }, "resources/shaders/demo_shader")
    defer destroy_shader_program(&program)

    testing.expect(t, ok, "ok check")
    nil_maybe: Maybe(u32)
    testing.expect_value(t, nil_maybe, program.id)
    log.infof("%#v", program)
    if len(program.shaders) == 2 {
        log.infof("%s, %s", program.shaders[0].type, program.shaders[0].source)
        log.infof("%s, %s", program.shaders[1].type, program.shaders[1].source)
    }
}