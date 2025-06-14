package demo

import win "../window"
import game "../game"
import "../ecs"
import "../model"
import "../render_old"
import cutils "../camera_utils"
import cam "../camera"
import shader "../shader"

import "core:log"
import "core:math/linalg"
import glm "core:math/linalg/glsl"


// Implement your before_frame and every_frame procedures in a file like this
// APIs for ecs are dogwater right now
// Certain operations are done around this every frame, look inside game package
every_frame :: proc() -> (ok: bool) {

    // Update camera
    //copied_program := draw_properties.gpu_component.(shader.gl_GPUComponent).program
    //cutils.update_view(&copied_program)

    // Draw
   // render_old.draw_indexed_entities(game.Game.scene, "helmet_arch", "helmet_entity")

    // Swap
    ok = win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
    return
}


before_frame :: proc() -> (ok: bool) {

    arch, _ := ecs.scene_add_default_archetype(game.Game.scene, "entities")

    world_properties := ecs.WorldComponent{
        scale = { 0.5, 0.5, 0.5 }
    }

    model := helmet_model()
    ecs.archetype_add_entity(game.Game.scene, arch, "helmet_entity",
        ecs.make_component_data_untyped_s(&model, ecs.MODEL_COMPONENT),
        ecs.make_component_data_untyped_s(&world_properties, ecs.WORLD_COMPONENT),
    )

    program := shader.read_shader_source("resources/shaders/demo_pbr_shader") or_return


    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera(label = "helmet_cam", position = glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint

    game.add_event_hooks(
        game.HOOK_MOUSE_MOTION(),
        game.HOOK_CLOSE_WINDOW(),
        game.HOOKS_CAMERA_MOVEMENT()  // Only can be used after camera added to scene
    )
}


@(private)
helmet_model :: proc() -> (helmet_model: model.Model) {
    meshes, ok := model.load_and_extract_meshes("SciFiHelmet"); if !ok do return
    return model.Model{ meshes }
}