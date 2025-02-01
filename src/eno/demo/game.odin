package demo

import win "../window"
import game "../game"
import "../ecs"
import "../model"
import "../gpu"
import "../render"
import cutils "../camera_utils"
import cam "../camera"

import "core:log"
import "core:math/linalg"
import glm "core:math/linalg/glsl"


// Implement your before_frame and every_frame procedures in a file like this
// APIs for ecs are dogwater right now

// Certain operations are done around this every frame, look inside game package
every_frame :: proc() {

    // Update camera
    copied_program := draw_properties.gpu_component.(gpu.gl_GPUComponent).program
    cutils.update_view(&copied_program)

    // Draw
    render.draw_indexed_entities(game.Game.scene, "helmet_arch", "helmet_entity")

    // Swap
    ok := win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
}

draw_properties: ^gpu.DrawProperties

before_frame :: proc() {

    helmet_arch, _ := ecs.scene_add_archetype(game.Game.scene, "helmet_arch", context.allocator,
        ecs.make_component_info(gpu.DrawProperties, "draw_properties"),
        ecs.make_component_info(linalg.Vector3f32, "position"),
        ecs.make_component_info(linalg.Vector3f32, "scale")
    )

    position: linalg.Vector3f32 = { 0.0, 0.0, 0.0 }
    scale: linalg.Vector3f32 = { 0.5, 0.5, 0.5 }


    helmet_draw_properties: gpu.DrawProperties

    helmet_draw_properties.mesh, helmet_draw_properties.indices = helmet_mesh_and_indices()
    ok := create_shader_program(&helmet_draw_properties); if !ok do return

    gpu.express_draw_properties(&helmet_draw_properties)


    ecs.archetype_add_entity(game.Game.scene, helmet_arch, "helmet_entity",
        ecs.make_component_data_untyped_s(&helmet_draw_properties, "draw_properties"),
        ecs.make_component_data_untyped_s(&position, "position"),
        ecs.make_component_data_untyped_s(&scale, "scale")
    )

    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera(label = "helmet_cam", position = glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint

    ok = set_uniforms(&helmet_draw_properties); if !ok do return

    draw_properties_ret, ecs_ok := ecs.query_component_from_archetype(helmet_arch, "draw_properties", gpu.DrawProperties, "helmet_entity"); if !ecs_ok do return
    draw_properties = draw_properties_ret[0].data

    game.add_event_hooks(
        game.HOOK_MOUSE_MOTION(),
        game.HOOK_CLOSE_WINDOW(),
        game.HOOKS_CAMERA_MOVEMENT()  // Only can be used after camera added to scene
    )
}


set_uniforms :: proc(draw_properties: ^gpu.DrawProperties) -> (ok: bool) {
    gl_comp := draw_properties.gpu_component.(gpu.gl_GPUComponent)
    program := &gl_comp.program

    // Get scale and position
    archetype := ecs.scene_get_archetype(game.Game.scene, "helmet_arch") or_return
    position_res: []ecs.ComponentData(glm.vec3) = ecs.query_component_from_archetype(archetype, "position", glm.vec3, "helmet_entity") or_return
    assert(len(position_res) == 1)

    scale_res: []ecs.ComponentData(glm.vec3) = ecs.query_component_from_archetype(archetype, "scale", glm.vec3, "helmet_entity") or_return
    assert(len(scale_res) == 1)

    position: ^glm.vec3 = position_res[0].data
    scale: ^glm.vec3 = scale_res[0].data


    model := glm.mat4Scale(scale^)
    model *= glm.mat4Translate(position^)

    gpu.set_matrix_uniform(program, "m_Model", 1, false, model)

    cutils.update_view(program)

    perspective := cam.get_perspective(game.Game.scene.viewpoint)
    gpu.set_matrix_uniform(program, "m_Projection", 1, false, perspective)

    draw_properties.gpu_component = gl_comp
    ok = true
    return
}


@(private)
helmet_mesh_and_indices :: proc() -> (mesh: model.Mesh, indices: model.IndexData) {
    meshes, index_datas, ok := model.load_and_extract_meshes("SciFiHelmet"); if !ok do return
    return meshes[0], index_datas[0]
}


@(private)
create_shader_program :: proc(properties: ^gpu.DrawProperties) -> (ok: bool) {
    sources := make([dynamic]gpu.ShaderSource, 0)
    gl_comp := properties.gpu_component.(gpu.gl_GPUComponent)
    gl_comp.program = gpu.init_shader_program()

    vertex_shader: gpu.Shader
    gpu.shader_layout_from_mesh(&vertex_shader, properties.mesh) or_return

    gpu.add_uniforms(&vertex_shader, { .mat4, "m_Model" })
    gpu.add_uniforms(&vertex_shader, { .mat4, "m_View" })
    gpu.add_uniforms(&vertex_shader, { .mat4, "m_Projection" })

    gpu.add_output(&vertex_shader, { .vec3, "fragColour" })

    gpu.add_functions(&vertex_shader, gpu.init_shader_function(
        .void,
        "main",
        `
            mat4 mvp = m_Projection * m_View * m_Model;
            gl_Position = mvp * vec4(position, 1.0);
            fragColour = position;
        `,
        false
    ))

    append(&sources, gpu.build_shader_source(vertex_shader, .VERTEX) or_return)
    log.infof("Built source: %#v", sources[0].source)


    fragment_shader: gpu.Shader
    gpu.add_output(&fragment_shader, { .vec4, "Colour" })
    gpu.add_input(&fragment_shader, { .vec3, "fragColour" })
    gpu.add_functions(&fragment_shader, gpu.init_shader_function(
        .void,
        "main",
        "   Colour = vec4(fragColour, 1.0);",
        false
    ))

    append(&sources, gpu.build_shader_source(fragment_shader, .FRAGMENT) or_return)
    log.infof("Built source: %#v", sources[1].source)

    gl_comp.program.sources = sources
    gpu.express_shader(&gl_comp.program)

    gpu.attach_program(gl_comp.program)
    gpu.register_uniform(&gl_comp.program, "m_Model")
    gpu.register_uniform(&gl_comp.program, "m_View")
    gpu.register_uniform(&gl_comp.program, "m_Projection")

    properties.gpu_component = gl_comp
    ok = true
    return
}