package tests

import "vendor:cgltf"
import gl "vendor:OpenGL"

import "../model"
import "../utils"
import "../shader"
import "../gpu"
import dbg "../debug"

import "core:testing"
import "core:log"


@(test)
copy_slice_to_dynamic_test :: proc(t: ^testing.T) {
    slice_inp := model.make_vertex_components([]uint{3, 3}, []cgltf.attribute_type{cgltf.attribute_type.normal, cgltf.attribute_type.position})
    dyna := make([dynamic]model.VertexComponent, 0)
    defer delete(dyna)

    utils.copy_slice_to_dynamic(&dyna, slice_inp)

    log.infof("dyna: \n%#v", dyna)
    testing.expect_value(t, len(dyna), len(slice_inp))
    for i := 0; i < len(dyna); i += 1 do testing.expect_value(t, dyna[i], slice_inp[i])
}


@(private)
create_test_render_context :: proc() -> (window: ^SDL.Window, gl_context: SDL.GLContext) {

	window = SDL.CreateWindow("eno engine test win", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, 400, 400, {.OPENGL})
	if window == nil {
		fmt.eprintln("Failed to create window")
		return window, gl_context 
	}
	
    dbg.init_debug_stack()
	gl_context = SDL.GL_CreateContext(window)
	SDL.GL_MakeCurrent(window, gl_context)
	gl.load_up_to(4, 3, SDL.gl_set_proc_address)

    _attr_ret: i32
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_FLAGS, i32(SDL.GLcontextFlag.DEBUG_FLAG))
    if _attr_ret != 0 do log.errorf("Could not set certain SDL parameters for OpenGL")

    gl.Enable(gl.DEBUG_OUTPUT)
    gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
    gl.DebugMessageCallback(dbg.GL_DEBUG_CALLBACK, nil)

    return window, gl_context 
}

@(test)
express_shader_test :: proc(t: ^testing.T) {
    using shader
    window, gl_context := create_test_render_context()
    defer dbg.destroy_debug_stack()
    
    vertex_shader: ^Shader = init_shader(
                []ShaderLayout {
                    { 0, .vec3, "a_position"},
                    { 1, .vec4, "a_colour"}
                }
        )
    add_output(vertex_shader, []ShaderInput {
        { .vec4, "v_colour"}
    })
    add_uniforms(vertex_shader, []ShaderUniform {
        { .mat4, "u_transform"}
    })
    add_functions(vertex_shader, []ShaderFunction {
        { 
            .void,
            []ShaderFunctionArgument {},
            "main",
            `    gl_Position = u_transform * vec4(a_position, 1.0);
    v_colour = a_colour;`,
            false
        }
    })

    vertex_source, vertex_ok := build_shader_source(vertex_shader, .VERTEX)
    testing.expect(t, vertex_ok, "vert check")

    
    fragment_shader: ^Shader = init_shader()
    add_input(fragment_shader, []ShaderInput {
        { .vec4, "v_colour" }
    })
    add_output(fragment_shader, []ShaderInput {
        { .vec4, "o_colour" }
    })
    add_functions(fragment_shader, []ShaderFunction {
        { 
            .void,
            []ShaderFunctionArgument {},
            "main",
            `    o_colour = v_colour;`,
            false
        }
    })

    fragment_source, fragment_ok := build_shader_source(fragment_shader, .FRAGMENT)
    testing.expect(t, fragment_ok, "frag ok check")

    program: ^ShaderProgram = init_shader_program([]^ShaderSource {
        vertex_source, fragment_source 
    })
    defer destroy_shader_program(program)
    
    testing.expect(t, !program.expressed, "not expressed check")

    express_ok := express_shader(program)
    testing.expect(t, express_ok, "express ok check")

    testing.expect(t, program.expressed, "expressed check")
}
