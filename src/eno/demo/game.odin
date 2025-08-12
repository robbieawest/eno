package demo

import win "../window"
import game "../game"
import "../ecs"
import "../resource"
import cutils "../camera_utils"
import "../standards"

import "core:strings"
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
    // set_light_position() or_return
    render.render(&game.Game.resource_manager, (cast(^GameData)game.Game.game_data).render_pipeline, game.Game.scene) or_return

    // Swap
    ok = win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
    free_all(context.temp_allocator)
    return
}


before_frame :: proc() -> (ok: bool) {

    arch := ecs.scene_add_default_archetype(game.Game.scene, "demo_entities") or_return

    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/SciFiHelmet/glTF/SciFiHelmet.gltf") or_return
    defer resource.destroy_model_scene_result(scene_res)

    models := scene_res.models
    second_helmet := models[0]
    second_helmet.model.name = strings.clone("SciFiHelmet2")
    second_helmet.world_comp = standards.make_world_component(position=glm.vec3{ 3.0, 0.0, 3.0 })
    append(&models, second_helmet)

    ecs.add_models_to_arch(game.Game.scene, arch, ..models[:]) or_return

    game_data := new(GameData)

    frame_buffers := []render.FrameBuffer {
        render.make_ibl_framebuffer()
    }

    game_data.render_pipeline = render.init_render_pipeline(1, 1, frame_buffers)

    window_res := win.get_window_resolution(game.Game.window) or_return
    game_data.render_pipeline.passes[0] = render.make_render_pass(
        game_data.render_pipeline,
        nil,
        render.RenderPassQuery{},
        render.RenderPassShaderGenerate.LIGHTING,
        render.RenderPassProperties{
            geometry_z_sorting = .ASC,
            face_culling = render.Face.BACK,
            viewport = [4]i32{ 0, 0, window_res.w, window_res.h },
            render_skybox = true,
            clear = { .COLOUR_BIT, .DEPTH_BIT },
            multisample = true
        }
    ) or_return

    game_data.render_pipeline.pre_passes[0] = render.make_pre_render_pass(
        game_data.render_pipeline,
        render.IBLInput{},
        0
    ) or_return

    game.Game.game_data = game_data

    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera(label = "cam", position = glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint

    // todo copy light name internally
    light := resource.PointLight{ "demo_light", false, 10.0, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ 3.0, 3.0, 0.0 } }
    light_comp := standards.make_world_component(position=light.position)
    light2 := resource.PointLight{ "demo_light2", false, 10.0, glm.vec3{ 1.0, 0.0, 0.0 }, glm.vec3{ -5.0, 0.0, 0.0 } }
    light_comp2 := standards.make_world_component(position=light2.position)

    light_arch := ecs.scene_add_archetype(game.Game.scene, "lights",
        cast(ecs.ComponentInfo)(resource.LIGHT_COMPONENT),
        cast(ecs.ComponentInfo)(resource.MODEL_COMPONENT),
        cast(ecs.ComponentInfo)(standards.WORLD_COMPONENT),
        cast(ecs.ComponentInfo)(standards.VISIBLE_COMPONENT),
    ) or_return

    ecs.archetype_add_entity(game.Game.scene, light_arch, light.name,
        ecs.make_ecs_component_data(resource.LIGHT_COMPONENT.label, resource.LIGHT_COMPONENT.type, resource.Light(light)),
        ecs.make_ecs_component_data(resource.MODEL_COMPONENT.label, resource.MODEL_COMPONENT.type, resource.make_light_billboard(&game.Game.resource_manager) or_return),
        ecs.make_ecs_component_data(standards.WORLD_COMPONENT.label, standards.WORLD_COMPONENT.type, light_comp),
        ecs.make_ecs_component_data(standards.VISIBLE_COMPONENT.label, standards.VISIBLE_COMPONENT.type, false),
    )

    ecs.archetype_add_entity(game.Game.scene, light_arch, light2.name,
        ecs.make_ecs_component_data(resource.LIGHT_COMPONENT.label, resource.LIGHT_COMPONENT.type, resource.Light(light2)),
        ecs.make_ecs_component_data(resource.MODEL_COMPONENT.label, resource.MODEL_COMPONENT.type, resource.make_light_billboard(&game.Game.resource_manager) or_return),
        ecs.make_ecs_component_data(standards.WORLD_COMPONENT.label, standards.WORLD_COMPONENT.type, light_comp2),
        ecs.make_ecs_component_data(standards.VISIBLE_COMPONENT.label, standards.VISIBLE_COMPONENT.type, false),
    )

    game.add_event_hooks(
        game.HOOK_MOUSE_MOTION(),
        game.HOOK_CLOSE_WINDOW(),
        game.HOOKS_CAMERA_MOVEMENT()  // Only can be used after camera added to scene
    )

    manager := &game.Game.resource_manager
    render.populate_all_shaders(&game_data.render_pipeline, manager, game.Game.scene) or_return

    game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "newport_loft.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "park_music_stage_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "rogland_clear_night_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "twilight_sunset_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "voortrekker_interior_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "metro_noord_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "drackenstein_quarry_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "fireplace_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "freight_station_4k.hdr") or_return
    // game.Game.scene.image_environment = ecs.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "golden_bay_4k.hdr") or_return
    render.pre_render(manager, game_data.render_pipeline, game.Game.scene) or_return

    return true
}

set_light_position :: proc() -> (ok: bool) {
    isVisibleQueryData := true
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = resource.LIGHT_COMPONENT.label, action = .QUERY_AND_INCLUDE },
        { label = standards.WORLD_COMPONENT.label, action = .NO_QUERY_BUT_INCLUDE },
        { label = standards.VISIBLE_COMPONENT.label, action = .QUERY_NO_INCLUDE, data = &isVisibleQueryData }
    }}
    query_result := ecs.query_scene(game.Game.scene, query) or_return

    lights := ecs.get_component_from_query_result(query_result, resource.Light, resource.LIGHT_COMPONENT.label) or_return
    worlds := ecs.get_component_from_query_result(query_result, standards.WorldComponent, standards.WORLD_COMPONENT.label) or_return

    light := &lights[0].(resource.PointLight)
    time_seconds := f64(game.Game.meta_data.time_elapsed) / 1.0e9
    time_seconds *= 2
    light.position.x = 3.0 * f32(math.sin_f64(time_seconds))
    light.position.z = 3.0 * f32(math.sin_f64(time_seconds + math.PI / 2))

    worlds[0].position = light.position

    return true
}