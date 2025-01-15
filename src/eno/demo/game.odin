package demo

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"
import "vendor:cgltf"

import win "../window"
import game "../game"
import "../ecs"
import "../model"
import "../gpu"
import "../render"

import "core:log"
import "core:math/linalg"

// Implement your before_frame and every_frame procedures in a file like this
// APIs for ecs are dogwater right now

every_frame :: proc() {
    render.draw_indexed_entities(game.Game.scene, "helmet_arch", "helmet_entity")
    ok := win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
}


before_frame :: proc() {

    ok := game.map_sdl_events(
        { SDL.EventType.QUIT, proc() { game.quit_game() }}
    ); if !ok do log.errorf("Could not map SDL event")

    ok = game.map_sdl_key_events(
        { SDL.Keycode.ESCAPE, proc() { game.quit_game() }}
    ); if !ok do log.errorf("Could not map SDL key event")


    helmet_arch, _ := ecs.scene_add_archetype(game.Game.scene, "helmet_arch", context.allocator,
        ecs.make_component_info(gpu.DrawProperties, "draw_properties"),
        ecs.make_component_info(linalg.Vector3f32, "position"),
        ecs.make_component_info(linalg.Vector3f32, "scale")
    )

    position: linalg.Vector3f32
    scale: linalg.Vector3f32 = { 1.0, 1.0, 1.0 }


    helmet_draw_properties: gpu.DrawProperties
    helmet_draw_properties.mesh, helmet_draw_properties.indices = helmet_mesh_and_indices()
    ok = create_shader_program(&helmet_draw_properties); if !ok do return

    /*
    helmet_gl_comp.program, ok = gpu.read_shader_source({ Express = true }, "./resources/shaders/demo_shader")
    if !ok {
        log.errorf("Error while reading shader source, returning.")
        return
    }
    helmet_draw_properties.gpu_component = helmet_gl_comp
    */

    gpu.express_draw_properties(&helmet_draw_properties)

    ecs.archetype_add_entity(game.Game.scene, helmet_arch, "helmet_entity",
        ecs.make_component_data_untyped_s(&helmet_draw_properties, "draw_properties"),
        ecs.make_component_data_untyped_s(&position, "position"),
        ecs.make_component_data_untyped_s(&scale, "scale")
    )


    // Camera

}



@(private)
helmet_mesh_and_indices :: proc() -> (mesh: model.Mesh, indices: model.IndexData) {
    meshes, index_datas := read_meshes_and_indices_from_gltf("SciFiHelmet")
    return meshes[0], index_datas[0]
}


// Move this into gltf.odin
@(private)
read_meshes_and_indices_from_gltf :: proc(model_name: string) -> (meshes: []model.Mesh, indices: []model.IndexData) {
    data, result := model.load_gltf_mesh(model_name)
    assert(result == .success, "gltf read success assertion") // todo switch to log
    assert(len(data.meshes) > 0, "gltf data meshes available assertion")

    ok := false
    meshes, ok = model.extract_cgltf_mesh(&data.meshes[0])
    if !ok {
        log.error("Failed to read mesh")
        return meshes, indices
    }
    indices, ok = model.extract_index_data_from_mesh(&data.meshes[0])
    if !ok {
        log.error("Failed to read indices")
        return meshes, indices
    }

    return meshes, indices
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
    gpu.add_uniforms(&vertex_shader, { .mat4, "m_Perspective" })

    gpu.add_functions(&vertex_shader, gpu.init_shader_function(
        .void,
        "main",
        `   mat4 mvp = m_Model * m_View * m_Perspective;
            gl_Position = mvp * vec4(position, 1.0);
        `,
        false
    ))

    append(&sources, gpu.build_shader_source(vertex_shader, .VERTEX) or_return)
    log.infof("Built source: %#v", sources[0].source)


    fragment_shader: gpu.Shader
    gpu.add_output(&fragment_shader, { .vec4, "Colour" })
    gpu.add_functions(&fragment_shader, gpu.init_shader_function(
        .void,
        "main",
        "   Colour = vec4(1.0, 0.0, 0.0, 1.0);",
        false
    ))

    append(&sources, gpu.build_shader_source(fragment_shader, .FRAGMENT) or_return)
    log.infof("Built source: %#v", sources[1].source)

    gl_comp.program.sources = sources
    gpu.express_shader(&gl_comp.program)

    gpu.attach_program(gl_comp.program)
    gpu.register_uniform(&gl_comp.program, "m_Model")
    gpu.register_uniform(&gl_comp.program, "m_View")
    gpu.register_uniform(&gl_comp.program, "m_Perspective")

    properties.gpu_component = gl_comp
    ok = true
    return
}