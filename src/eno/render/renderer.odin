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


draw_indexed_entities :: proc{ draw_indexed_entities_noarch, draw_indexed_entities_arch }

draw_indexed_entities_arch :: proc(archetype: ^ecs.Archetype, entity_labels: ..string) -> (ok: bool) {
    draw_properties_ret: []ecs.ComponentData(gpu.DrawProperties) = ecs.query_component_from_archetype(archetype, "draw_properties", gpu.DrawProperties) or_return

    for draw_properties_comp in draw_properties_ret {
        draw_properties: ^gpu.DrawProperties = draw_properties_comp.data
        gpu.draw_elements(draw_properties)
    }

    ok = true
    return
}

draw_indexed_entities_noarch :: proc(scene: ^ecs.Scene, archetype_label: string, entity_labels: ..string) -> (ok: bool) {
    archetype: ^ecs.Archetype = ecs.scene_get_archetype(scene, archetype_label) or_return
    return draw_indexed_entities_arch(archetype, ..entity_labels)
}

/*
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

    //gl_comp: ^gpu.gl_GPUComponent = &draw_properties.gpu_component.(gpu.gl_GPUComponent)
    gl_comp.program = program^

    return true
}
*/