package demo

import win "../window"
import game "../game"
import "../ecs"
import "../resource"
import cutils "../camera_utils"
import "../standards"

import "core:log"
import glm "core:math/linalg/glsl"
import render "../render"


// Implement your before_frame and every_frame procedures in a file like this
// Certain operations are done around this every frame, look inside game package

// programmer-defined to be able to store any data
// set a pointer to Game.game_Data
GameData :: struct {
    render_pipeline: render.RenderPipeline
}

every_frame :: proc() -> (ok: bool) {

    render.render(&game.Game.resource_manager, (cast(^GameData)game.Game.game_data).render_pipeline, game.Game.scene)

    // Swap
    ok = win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
    return
}


before_frame :: proc() -> (ok: bool) {

    arch := ecs.scene_add_default_archetype(game.Game.scene, "demo_entities") or_return

    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/SciFiHelmet/glTF/SciFiHelmet.gltf") or_return
    // Not expecting any lights from this
    helmet_model := scene_res.models[0].model
    world_properties := scene_res.models[0].world_comp

    ecs.archetype_add_entity(game.Game.scene, arch, "helmet_entity",
        ecs.make_ecs_component_data(resource.MODEL_COMPONENT.label, resource.MODEL_COMPONENT.type, ecs.serialize_data(&helmet_model, size_of(resource.Model))),
        ecs.make_ecs_component_data(standards.WORLD_COMPONENT.label, standards.WORLD_COMPONENT.type, ecs.serialize_data(&world_properties, size_of(standards.WorldComponent))),
        ecs.make_ecs_component_data(standards.VISIBLE_COMPONENT.label, standards.VISIBLE_COMPONENT.type, ecs.serialize_data(true, size_of(bool)))
    ) or_return


    game_data := new(GameData)
    render_passes := make([dynamic]render.RenderPass)
    append_elems(&render_passes, render.RenderPass{}) // default render pass signifies lighting pass
    game_data.render_pipeline = render.RenderPipeline{ render_passes }
    game.Game.game_data = game_data

    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera(label = "cam", position = glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint

    game.add_event_hooks(
        game.HOOK_MOUSE_MOTION(),
        game.HOOK_CLOSE_WINDOW(),
        game.HOOKS_CAMERA_MOVEMENT()  // Only can be used after camera added to scene
    )

    return true
}