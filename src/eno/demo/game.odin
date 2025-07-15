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
import "core:math"


// Implement your before_frame and every_frame procedures in a file like this
// Certain operations are done around this every frame, look inside game package

// programmer-defined to be able to store any data
// set a pointer to Game.game_Data
GameData :: struct {
    render_pipeline: render.RenderPipeline
}

every_frame :: proc() -> (ok: bool) {
    set_light_position()
    render.render(&game.Game.resource_manager, (cast(^GameData)game.Game.game_data).render_pipeline, game.Game.scene) or_return

    // Swap
    ok = win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
    return
}


before_frame :: proc() -> (ok: bool) {

    arch := ecs.scene_add_default_archetype(game.Game.scene, "demo_entities") or_return

    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/SciFiHelmet/glTF/SciFiHelmet.gltf") or_return
    log.infof("num model meshes: %#v", len(scene_res.models[0].model.meshes))

    ecs.add_models_to_arch(game.Game.scene, arch, ..scene_res.models[:]) or_return

    game_data := new(GameData)
    render_passes := make([dynamic]render.RenderPass)
    append_elems(&render_passes, render.RenderPass{}) // default render pass signifies lighting pass
    game_data.render_pipeline = render.RenderPipeline{ render_passes }
    game.Game.game_data = game_data

    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera(label = "cam", position = glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint

    // todo copy light name internally
    light := resource.PointLight{ "demo_light", true, 1.0, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ 1.0, 1.0, 1.0 } }
    ecs.scene_add_lights(game.Game.scene, light)

    game.add_event_hooks(
        game.HOOK_MOUSE_MOTION(),
        game.HOOK_CLOSE_WINDOW(),
        game.HOOKS_CAMERA_MOVEMENT()  // Only can be used after camera added to scene
    )

    return true
}

set_light_position :: proc() {
    light := &game.Game.scene.light_sources.point_lights[0]
    time_seconds := f64(game.Game.meta_data.time_elapsed) / 1.0e9
    time_seconds *= 2
    light.position.x = 1.0 * f32(math.sin_f64(time_seconds))
    light.position.z = 1.0 * f32(math.sin_f64(time_seconds + math.PI / 2))
}