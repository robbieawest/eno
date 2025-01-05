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
// APIs for gltf interop and ecs are dogwater right now

every_frame :: proc() {
    render.draw_indexed_entities(game.Game.scene, "helmet_arch", "helmet_entity")
    ok := win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
}


before_frame :: proc() {

    // I'd like for these event and keycode values to be migrated to eno constants from SDL
    ok := game.map_sdl_events([]game.SDLEventPair {
        { SDL.EventType.QUIT, proc() { game.quit_game() }}
    }); if !ok do log.errorf("Could not map SDL event")

    ok = game.map_sdl_key_events([]game.SDLKeyActionPair {
        { SDL.Keycode.ESCAPE, proc() { game.quit_game() }}
    }); if !ok do log.errorf("Could not map SDL key event")


    helmet_arch, _ := ecs.scene_add_archetype(game.Game.scene, "helmet_arch", context.allocator,
        ecs.make_component_info(gpu.DrawProperties, "draw_properties"),
        ecs.make_component_info(linalg.Vector3f32, "position")
    )

    position: linalg.Vector3f32
    helmet_draw_properties: gpu.DrawProperties
    helmet_draw_properties.mesh, helmet_draw_properties.indices = helmet_mesh_and_indices()

    gpu_component: ^gpu.gl_GPUComponent = &helmet_draw_properties.gpu_component.(gpu.gl_GPUComponent)
    gpu_component.program, ok = gpu.read_shader_source({ Express = true }, "./resources/shaders/demo_shader")
    if !ok {
        log.errorf("Error while reading shader source, returning.")
        return
    }

    gpu.express_draw_properties(&helmet_draw_properties)

    ecs.archetype_add_entity(game.Game.scene, helmet_arch, "helmet_entity",
        ecs.make_component_data_untyped_s(&helmet_draw_properties, "draw_properties"),
        ecs.make_component_data_untyped_s(&position, "position")
    )


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
