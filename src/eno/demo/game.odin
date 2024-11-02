package demo

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"
import "vendor:cgltf"

import win "../window"
import game "../game"
import "../ecs"
import "../model"

import "core:log"

// Implement your before_frame and every_frame procedures in a file like this
// APIs for gltf interop and ecs are dogwater right now

every_frame :: proc(eno_game: ^game.EnoGame) {
    ok := win.swap_window_bufs(eno_game.window); if !ok do log.errorf("could not swap bufs")
}


before_frame :: proc(eno_game: ^game.EnoGame) {
    
    ok := game.map_sdl_events(eno_game, []game.SDLEventPair {
        { SDL.EventType.QUIT, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL event")

    ok = game.map_sdl_key_events(eno_game, []game.SDLKeyActionPair {
        { SDL.Keycode.ESCAPE, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL key event")



    game_scene := ecs.init_scene()
    helmet_arch := ecs.init_archetype("scifi-helmet", []ecs.LabelledComponent {
        ecs.LabelledComponent { label = "position", component = ecs.DEFAULT_CENTER_POSITION },
        ecs.LabelledComponent { label = "draw_properties", component = ecs.DEFAULT_DRAW_PROPERTIES },
    })
    ecs.add_arch_to_scene(game_scene, helmet_arch)
    
    
    ecs.add_entities_of_archetype("scifi-helmet", 1, game_scene)

    archOperands := []string{"scifi-helmet"}
    compOperands := []string{"draw_properties"}
    query := ecs.search_query(archOperands, compOperands, 1, nil)
    defer free(query)

    mesh, indices := create_mesh_and_indices()

    draw_props := ecs.DEFAULT_DRAW_PROPERTIES
    draw_props.mesh = mesh
    draw_props.indices = indices
    updated_components := [][][]ecs.Component{ [][]ecs.Component{ []ecs.Component{ draw_props } } }

    result: ecs.QueryResult = ecs.set_components(query, updated_components[:], game_scene)
    defer ecs.destroy_query_result(result)
}



@(private)
create_mesh_and_indices :: proc() -> (mesh: model.Mesh, indices: model.IndexData) {
    
    vertex_layout := model.VertexLayout { []uint{3, 3, 4, 2}, []cgltf.attribute_type {
            cgltf.attribute_type.normal,
            cgltf.attribute_type.position,
            cgltf.attribute_type.tangent,
            cgltf.attribute_type.texcoord
    }}

    meshes, index_datas := read_meshes_and_indices_from_gltf("SciFiHelmet", []^model.VertexLayout{ &vertex_layout })
    return meshes[0], index_datas[0]
}


// Move this into gltf.odin
@(private)
read_meshes_and_indices_from_gltf :: proc(model_name: string, vertex_layouts: []^model.VertexLayout) -> (meshes: []model.Mesh, indices: []model.IndexData) {
    data, result := model.load_gltf_mesh(model_name)
    assert(result == .success, "gltf read success assertion")
    assert(len(data.meshes) > 0, "gltf data meshes available assertion")

    ok := false
    meshes, ok = model.extract_mesh_from_cgltf(&data.meshes[0], vertex_layouts)
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
