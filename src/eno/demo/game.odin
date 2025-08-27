package demo

import win "../window"
import game "../game"
import "../ecs"
import "../resource"
import cutils "../camera_utils"
import "../standards"
import "../ui"

import "core:strings"
import "core:log"
import glm "core:math/linalg/glsl"
import render "../render"
import "core:math"


// Implement your before_frame and every_frame procedures in a file like this
// Certain operations are done around this every frame, look inside game package

every_frame :: proc() -> (ok: bool) {
    // set_light_position() or_return
    render.render(&game.Game.resource_manager, game.Game.scene) or_return

    // Swap
    ok = win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
    free_all(context.temp_allocator)
    return
}

load_supra :: proc(arch: ^ecs.Archetype) -> (ok: bool) {

    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/Supra/scene.gltf") or_return
    models := scene_res.models

    supra := &models[0]
    // supra.world_comp.rotation =

    defer resource.destroy_model_scene_result(scene_res)
    ecs.add_models_to_arch(game.Game.scene, arch, ..models[:]) or_return
    return true
}

load_sword :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/gradient_fantasy_sword/scene.gltf") or_return
    defer resource.destroy_model_scene_result(scene_res)
    models := scene_res.models

    models[0].model.meshes[0].transpose_transformation = true

    log.infof("world: %#v", models[0].world_comp)

    ecs.add_models_to_arch(game.Game.scene, arch, ..models[:]) or_return
    return true
}

load_clearcoat_test :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/CompareClearcoat/glTF/CompareClearcoat.gltf") or_return
    models := scene_res.models
    defer resource.destroy_model_scene_result(scene_res)
    ecs.add_models_to_arch(game.Game.scene, arch, ..models[:]) or_return
    return true
}

load_helmet :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/SciFiHelmet/glTF/SciFiHelmet.gltf") or_return

    models := scene_res.models
    second_helmet := models[0]
    second_helmet.model.name = strings.clone("model clone")
    second_helmet.world_comp = standards.make_world_component(position=glm.vec3{ 3.0, 0.0, 3.0 })
    append(&models, second_helmet)

    defer resource.destroy_model_scene_result(scene_res)
    ecs.add_models_to_arch(game.Game.scene, arch, ..models[:]) or_return
    return true
}

load_dhelmet :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, "./resources/models/DamagedHelmet/glTF/DamagedHelmet.gltf") or_return

    models := scene_res.models

    defer resource.destroy_model_scene_result(scene_res)
    ecs.add_models_to_arch(game.Game.scene, arch, ..models[:]) or_return
    return true
}

before_frame :: proc() -> (ok: bool) {

    arch := ecs.scene_add_default_archetype(game.Game.scene, "demo_entities") or_return
    load_supra(arch) or_return

    render.init_render_pipeline()

    window_res := win.get_window_resolution(game.Game.window)

    background_colour := [4]f32{ 1.0, 1.0, 1.0, 1.0 }
    background_colour_factor: f32 = 0.85
    render.add_render_passes(
         render.make_render_pass(
            shader_gather=render.RenderPassShaderGenerate.LIGHTING,
            mesh_gather=render.RenderPassQuery{ material_query =
                proc(material: resource.Material, type: resource.MaterialType) -> bool {
                    return type.alpha_mode != .BLEND && !type.double_sided
                }
            },
            properties=render.RenderPassProperties{
                geometry_z_sorting = .ASC,
                face_culling = render.FaceCulling.BACK,
                viewport = [4]i32{ 0, 0, window_res.w, window_res.h },
                clear = { .COLOUR_BIT, .DEPTH_BIT },
                clear_colour = background_colour * background_colour_factor,
                multisample = true
            }
        ) or_return,
    )
    render.add_render_passes(
        render.make_render_pass(
            shader_gather=render.Context.pipeline.passes[0],
            mesh_gather=render.RenderPassQuery{ material_query =
                proc(material: resource.Material, type: resource.MaterialType) -> bool {
                    return type.alpha_mode != .BLEND && type.double_sided
                }
            },
            properties=render.RenderPassProperties{
                geometry_z_sorting = .ASC,
                viewport = [4]i32{ 0, 0, window_res.w, window_res.h },
                multisample = true,
                render_skybox = true,  // Rendering skybox will set certain properties indepdendent of what is set in the pass properties, it will also be done last in the pass
            },
        ) or_return,
        render.make_render_pass(
            shader_gather=render.Context.pipeline.passes[0],
            mesh_gather=render.RenderPassQuery{ material_query =
                proc(material: resource.Material, type: resource.MaterialType) -> bool {
                    return type.alpha_mode == .BLEND
                }
            },
            properties=render.RenderPassProperties{
                geometry_z_sorting = .DESC,
                face_culling = render.FaceCulling.ADAPTIVE,
                viewport = [4]i32{ 0, 0, window_res.w, window_res.h },
                multisample = true,
                blend_func = render.BlendFunc{ .SOURCE_ALPHA, .ONE_MINUS_SOURCE_ALPHA },
            },
        ) or_return
    ) or_return

    /* Setup for pre passes
    game_data.render_pipeline.pre_passes[0] = render.make_pre_render_pass(
        game_data.render_pipeline,
        render.IBLInput{},
        0
    ) or_return
    */

    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera(label = "cam", position = glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint

    light_arch := ecs.scene_add_archetype(game.Game.scene, "lights",
        cast(ecs.ComponentInfo)(resource.LIGHT_COMPONENT),
        cast(ecs.ComponentInfo)(resource.MODEL_COMPONENT),
        cast(ecs.ComponentInfo)(standards.WORLD_COMPONENT),
        cast(ecs.ComponentInfo)(standards.VISIBLE_COMPONENT),
    ) or_return

    lights := make([dynamic]resource.PointLight)
    defer delete(lights)

    light_height: f32 = 5.0
    light_dist: f32 = 5.0
    intensity: f32 = 3.0
    append_elems(&lights,
        resource.PointLight{ "demo_light", true, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ light_dist, light_height, light_dist } },
        resource.PointLight{ "demo_light2", true, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ light_dist, light_height, -light_dist } },
        resource.PointLight{ "demo_light3", true, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ -light_dist, light_height, light_dist } },
        resource.PointLight{ "demo_light4", true, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ -light_dist, light_height, -light_dist } },
        resource.PointLight{ "demo_light5", true, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ light_dist, light_height, 0.0 } },
        resource.PointLight{ "demo_light6", true, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ -light_dist, light_height, 0.0 } },
    )

    for light in lights {
        light_comp := standards.make_world_component(position=light.position)
        ecs.archetype_add_entity(game.Game.scene, light_arch, light.name,
            ecs.make_ecs_component_data(resource.LIGHT_COMPONENT.label, resource.LIGHT_COMPONENT.type, resource.Light(light)),
            ecs.make_ecs_component_data(resource.MODEL_COMPONENT.label, resource.MODEL_COMPONENT.type, resource.make_light_billboard_model(&game.Game.resource_manager, colour_override = light.colour) or_return),
            ecs.make_ecs_component_data(standards.WORLD_COMPONENT.label, standards.WORLD_COMPONENT.type, light_comp),
            ecs.make_ecs_component_data(standards.VISIBLE_COMPONENT.label, standards.VISIBLE_COMPONENT.type, true),
        )
    }


    game.add_event_hooks(
        game.HOOK_MOUSE_MOTION(),
        game.HOOK_CLOSE_WINDOW(),
        game.HOOKS_CAMERA_MOVEMENT(),
        game.HOOK_TOGGLE_UI_MOUSE()
    )

    manager := &game.Game.resource_manager
    render.populate_all_shaders(manager, game.Game.scene) or_return

    // render.make_image_environment(standards.TEXTURE_RESOURCE_PATH + "park_music_stage_4k.hdr") or_return

    // Use if you have pre render passes
    // render.pre_render(manager, game_data.render_pipeline, game.Game.scene) or_return

    ui.add_ui_elements(render.render_settings_ui_element) or_return
    ui.show_demo_window(true) or_return

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