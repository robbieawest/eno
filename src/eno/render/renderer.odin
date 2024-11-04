package render

import "../ecs"
import "../gpu"
import "../shader"
import dbg "../debug"

// Shitty beta renderer

render_all_from_scene :: proc(game_scene: ^ecs.Scene, create_default_program: bool) -> (ok: bool) {
    using ecs

    search_query: ^SearchQuery = search_query([]string{}, []string{ "draw_properties" }, 255, nil)
    search_result: ^QueryResult = search_scene(game_scene, search_query)
    dbg.debug_point()

    for arch_label, arch_res in search_result {

        for entity_label, entity_components in arch_res {
            
            for component in entity_components {
                draw_properties := component.(DrawProperties)

                b_is_drawable := gpu.component_is_drawable(component)
                if b_is_drawable != 0 {
                    if b_is_drawable & b0001 > 0 do draw_properties.gpu_component = gpu.express_mesh_vertices(&draw_properties.mesh, draw_properties.gpu_component) or_return
                    if b_is_drawable & b0010 > 0 do draw_properties.gpu_component = gpu.express_indices(&draw_properties.indices, draw_properties.gpu_component) or_return
                    if create_default_program && b_is_drawable & b0100 > 0 do assign_default_shader(&draw_properties) or_return
                }
                
                gpu.draw_elements(draw_properties.gpu_component)
            }
        }
    }
}

assign_default_shader :: proc(draw_properties: ^ecs.DrawProperties) -> (ok: bool) {
     
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
    vertex_source := build_shader_source(vertex_shader, .VERTEX) or_return

    
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

    fragment_source := build_shader_source(fragment_shader, .FRAGMENT) or_return

    program: ^shader.ShaderProgram = shader.init_shader_program([]^ShaderSource {
        vertex_source, fragment_source 
    })

    gl_comp: ^gpu.gl_GPUComponent = &draw_properties.gpu_component.(gpu.gl_GPUComponent)
    gl_comp.program = program^

    return true
}
