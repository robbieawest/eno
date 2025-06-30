package demo

import win "../window"
import game "../game"
import "../ecs"
import "../resource"
import cutils "../camera_utils"
import shader "../shader"
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

    render.render((cast(^GameData)game.Game.game_data).render_pipeline, game.Game.scene)

    // Swap
    ok = win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
    return
}


before_frame :: proc() -> (ok: bool) {

    arch := ecs.scene_add_default_archetype(game.Game.scene, "demo_entities") or_return

    world_properties := standards.WorldComponent {
        scale = { 0.5, 0.5, 0.5 }
    }

    helmet_model := resource.extract_model(&game.Game.resurce_manager, "../resources/models/SciFiHelmet/gLTF/SciFiHelmet.gltf", "SciFiHelmet") or_return

    ecs.archetype_add_entity(game.Game.scene, arch, "helmet_entity",
        ecs.make_ecs_component_data(resource.MODEL_COMPONENT.label, resource.MODEL_COMPONENT.type, ecs.serialize_data(&helmet_model)),
        ecs.make_ecs_component_data(standards.WORLD_COMPONENT.label, standards.WORLD_COMPONENT.type, ecs.serialize_data(&world_properties)),
    ) or_return

    // todo figure out where to store shader identifiers in entity data
    program := shader.read_shader_source("resources/shaders/demo_pbr_shader") or_return

    game_data := new(GameData)
    game_data.render_pipeline = render.RenderPipeline{}  // Default -> Draw directly to default framebuffer
    game.Game.game_data = game_data

    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera(label = "helmet_cam", position = glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint

    game.add_event_hooks(
        game.HOOK_MOUSE_MOTION(),
        game.HOOK_CLOSE_WINDOW(),
        game.HOOKS_CAMERA_MOVEMENT()  // Only can be used after camera added to scene
    )

    return true
}