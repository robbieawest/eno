package render

import "../ecs"
import "../gpu"
import "../shader"
import dbg "../debug"
import win "../window"
import "../model"

import glm "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:log"

// Shitty beta renderer

/*
    Renders all entities in the scene with the "draw_properties" component
    Simply doe a single render call for each entity, with glDrawElements for OpenGL

    Automatically expresses any entities which have mesh data on RAM not on VRAM
    Has an option to create a default shader program if not already initialized
*/
/*
render_all_from_scene :: proc(game_scene: ^ecs.Scene, create_default_program: bool) -> (ok: bool) {
    dbg.debug_point()

    using ecs

    query: ^SearchQuery = search_query([]string{}, []string{ "draw_properties" }, 255, nil)
    search_result: QueryResult = search_scene(game_scene, query)
    defer destroy_query_result(search_result)

    for arch_label, arch_res in search_result {

        for entity_label, entity_components in arch_res {
            
            for component in entity_components {
                draw_properties := component.(gpu.DrawProperties)
                b_is_drawable := gpu.component_is_drawable(draw_properties.gpu_component)
                if b_is_drawable != 0 {
                    if b_is_drawable & 0b0001 > 0 do gpu.express_mesh_vertices(&draw_properties.mesh, &draw_properties.gpu_component) or_return
                    if b_is_drawable & 0b0010 > 0 do gpu.express_indices(&draw_properties.indices, &draw_properties.gpu_component) or_return
                    if create_default_program && b_is_drawable & 0b0100 > 0 do assign_default_shader(&draw_properties) or_return
                }
                
                gpu.draw_elements(draw_properties)
            }
        }
    }

    return true
}
*/

render_all_from_scene :: proc(game_scene: ^ecs.Scene) -> (ok: bool) {
    archetype_query := ecs.ArchetypeQuery{ entities = []string{}, components = []ecs.ComponentQuery{ { label = "draw_properties", type = gpu.DrawProperties }}}
    for &archetype in game_scene.archetypes {
        ecs.act_on_archetype(&archetype, archetype_query, draw_action) or_return
    }

    ok = true
    return
}

@(private)
draw_action :: proc(component: Component) -> (ok: bool) {
    draw_properties: gpu.DrawProperties = ecs.component_deserialize(component)

    
    b_is_drawable := gpu.component_is_drawable(draw_properties.gpu_component)
    if b_is_drawable != 0 {
        if b_is_drawable & 0b0001 > 0 do gpu.express_mesh_vertices(&draw_properties.mesh, &draw_properties.gpu_component) or_return
        if b_is_drawable & 0b0010 > 0 do gpu.express_indices(&draw_properties.indices, &draw_properties.gpu_component) or_return
        if b_is_drawable & 0b0100 > 0 do assign_default_shader(&draw_properties) or_return
    }
    
    gpu.draw_elements(draw_properties)

    ok = true
    return
}


@(private)
shader_layout_from_mesh_layout :: proc(mesh_layout: ^model.VertexLayout) -> (shader_layout: [dynamic]shader.ShaderLayout) {

    shader_layout = make([dynamic]shader.ShaderLayout, len(mesh_layout.sizes))
    defer delete(shader_layout)
    
    found_position: bool
    for i: uint = 0; i < len(mesh_layout.sizes); i += 1 {
        layout_tag: string
        type: shader.GLSLDataType

        switch mesh_layout.types[i] {
        case .color, .tangent:
            type = .vec4
        case .position:
            found_position = true
            layout_tag = "a_position"
            fallthrough
        case .normal:
            type = .vec3
        case .texcoord:
            type = .vec2
        case .joints, .custom, .invalid, .weights:
            dbg.debug_point(dbg.LogInfo{ msg = "Unsupported mesh layout type", level = .WARN })
        }

        if layout_tag == "" do layout_tag = fmt.aprintf("unspecified layout tag %d", i)
        shader_layout[i] = { i, type, layout_tag } // check if possible!
    }

    return shader_layout
}

assign_default_shader :: proc(draw_properties: ^gpu.DrawProperties) -> (ok: bool) {
    using shader

    shader_layout: [dynamic]ShaderLayout = shader_layout_from_mesh_layout(draw_properties.mesh.layout)
    defer delete(shader_layout)

    vertex_shader: ^Shader = init_shader(slice.clone(shader_layout[:]))
    add_output(vertex_shader, []ShaderInput {
        { .vec4, "v_colour" }
    })
    add_uniforms(vertex_shader, []ShaderUniform {
        { .mat4, "u_transform" }
    })
    add_functions(vertex_shader, []ShaderFunction {
        { 
            .void,
            []ShaderFunctionArgument {},
            "main",
            `    gl_Position = u_transform * vec4(a_position, 1.0);
    v_colour = vec4(1.0, 0.0, 0.0, 1.0);`,
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

/*
    Updates the positions of entities on the GPU if:
    entity has the "position" component
    entity has the mat4 u_transform uniform which is available in the default_shader
     assigned in assign_default_shader
*/

/*
update_scene_positions :: proc(game_scene: ^ecs.Scene) -> (ok: bool) {
    using ecs
    query: ^SearchQuery = search_query([]string{}, []string{ "position", "draw_properties" }, 255, nil)
    log.info("now searching")
    search_result: QueryResult = search_scene(game_scene, query)
    defer destroy_query_result(search_result)

    log.info("hi")
    dbg.debug_point()
    log.info("hey")
    log.infof("scene searched: %#v", search_result)

    for arch_label, arch_res in search_result {

        for entity_label, entity_components in arch_res {

            position: ^CenterPosition
            draw_properties: ^gpu.DrawProperties

            for component in entity_components {
                #partial switch &val in component {
                case ecs.CenterPosition: 
                    position = &val
                case gpu.DrawProperties:
                    draw_properties = &val
                }
            }
            
            model_mat := glm.mat4Translate({ position.x, position.y, position.z })
            view_mat := glm.identity(glm.mat4)

            fov: f32 = 90.0
            aspect_ratio: f32 = f32(win.WINDOW_WIDTH) / f32(win.WINDOW_HEIGHT)
            persp_mat := glm.mat4Perspective(glm.radians(fov), aspect_ratio, 0.1, 100.0)

            mvp_mat := persp_mat * view_mat * model_mat
            gpu.shader_uniform_update_mat4(draw_properties, "u_transform", &mvp_mat[0, 0]) // ignore result
        }
    }

    return true
}
*/

update_scene_positions :: proc(game_scene: ^ecs.Scene) -> (ok: bool) {
    
}
