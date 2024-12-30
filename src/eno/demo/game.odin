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

every_frame :: proc(eno_game: ^game.EnoGame) {
    render.draw_indexed_entities(eno_game.scene, "helmet_arch", "helmet_entity")
    ok := win.swap_window_bufs(eno_game.window); if !ok do log.errorf("could not swap bufs")
}


before_frame :: proc(eno_game: ^game.EnoGame) {

    // I'd like for these event and keycode values to be migrated to eno constants from SDL
    ok := game.map_sdl_events(eno_game, []game.SDLEventPair {
        { SDL.EventType.QUIT, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL event")

    ok = game.map_sdl_key_events(eno_game, []game.SDLKeyActionPair {
        { SDL.Keycode.ESCAPE, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL key event")


    helmet_arch, _ := ecs.scene_add_archetype(eno_game.scene, "helmet_arch", context.allocator,
        ecs.make_component_info(gpu.DrawProperties, "draw_properties"),
        ecs.make_component_info(linalg.Vector3f32, "position")
    )


    position: linalg.Vector3f32
    helmet_draw_properties: gpu.DrawProperties
    helmet_draw_properties.mesh, helmet_draw_properties.indices = helmet_mesh_and_indices()
    gpu.express_draw_properties(&helmet_draw_properties)

    ecs.archetype_add_entity(eno_game.scene, helmet_arch, "helmet_entity",
        ecs.make_component_data_untyped_s(&helmet_draw_properties, "draw_properties"),
        ecs.make_component_data_untyped_s(&position, "position")
    )
}



@(private)
helmet_mesh_and_indices :: proc() -> (mesh: model.Mesh, indices: model.IndexData) {
    
    vertex_layout := model.VertexLayout { []u32{3, 3, 4, 2}, []cgltf.attribute_type {
            cgltf.attribute_type.normal,
            cgltf.attribute_type.position,
            cgltf.attribute_type.tangent,
            cgltf.attribute_type.texcoord
    }}

    meshes, index_datas := read_meshes_and_indices_from_gltf("SciFiHelmet", []model.VertexLayout{ vertex_layout })
    return meshes[0], index_datas[0]
}


// Move this into gltf.odin
@(private)
read_meshes_and_indices_from_gltf :: proc(model_name: string, vertex_layouts: []model.VertexLayout) -> (meshes: []model.Mesh, indices: []model.IndexData) {
    data, result := model.load_gltf_mesh(model_name)
    assert(result == .success, "gltf read success assertion") // todo switch to log
    assert(len(data.meshes) > 0, "gltf data meshes available assertion")

    ok := false
    meshes, ok = model.extract_cgltf_mesh(&data.meshes[0], vertex_layouts)
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
