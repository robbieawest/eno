package demo

import win "../window"
import game "../game"
import "../ecs"
import "../resource"
import cutils "../camera_utils"
import "../standards"
import "../ui"
import im "../../../libs/dear-imgui/"

import "core:fmt"
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

load_model :: proc(arch: ^ecs.Archetype, path: string) -> (ok: bool) {
    scene_res: resource.ModelSceneResult = resource.extract_gltf_scene(&game.Game.resource_manager, path) or_return
    models := scene_res.models

    for &model, i in models {
        mod := &model.model
        mod.name = fmt.aprintf("demo_entity %d", i)
    }

    for model in models do log.infof("model name: '%s'", model.model.name)

    defer resource.destroy_model_scene_result(scene_res)
    ecs.add_models_to_arch(game.Game.scene, arch, ..models[:]) or_return
    return true
}

load_supra :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    return load_model(arch, "./resources/models/Supra/scene.gltf")
}

load_sword :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    return load_model(arch, "./resources/models/gradient_fantasy_sword/scene.gltf")
}

load_clearcoat_test :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    return load_model(arch, "./resources/models/CompareClearcoat/glTF/CompareClearcoat.gltf")
}

load_helmet :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    return load_model(arch, "./resources/models/SciFiHelmet/glTF/SciFiHelmet.gltf")
}

load_dhelmet :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    return load_model(arch, "./resources/models/DamagedHelmet/glTF/DamagedHelmet.gltf")
}

demo_arch: ^ecs.Archetype
before_frame :: proc() -> (ok: bool) {

    arch := ecs.scene_add_default_archetype(game.Game.scene, "demo_entities") or_return
    demo_arch = ecs.scene_get_archetype(game.Game.scene, "demo_entities") or_return
    load_helmet(arch) or_return

    window_res := win.get_window_resolution(game.Game.window)

    render.init_render_context(&game.Game.resource_manager, window_res.w, window_res.h) or_return
    render.init_render_pipeline()

    gbuf_normal_output := render.make_gbuffer_passes(window_res.w, window_res.h, render.GBufferInfo{ .NORMAL, .DEPTH }) or_return
    ssao_output := render.make_ssao_passes(window_res.w, window_res.h, gbuf_normal_output.?) or_return

    background_colour := [4]f32{ 1.0, 1.0, 1.0, 1.0 }
    background_colour_factor: f32 = 0.01
    render.make_lighting_passes(window_res, background_colour * background_colour_factor, ssao_output) or_return

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
    light_height: f32 = 2.0
    light_dist: f32 = 2.0
    intensity: f32 = 2.2
    enabled := true
    append_elems(&lights,
        resource.PointLight{ "demo_light", enabled, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ light_dist, light_height, light_dist } },
        resource.PointLight{ "demo_light2", enabled, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ light_dist, light_height, -light_dist } },
        resource.PointLight{ "demo_light3", enabled, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ -light_dist, light_height, light_dist } },
        resource.PointLight{ "demo_light4", enabled, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ -light_dist, light_height, -light_dist } },
        resource.PointLight{ "demo_light5", enabled, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ light_dist, light_height, 0.0 } },
        resource.PointLight{ "demo_light6", enabled, intensity, glm.vec3{ 1.0, 1.0, 1.0 }, glm.vec3{ -light_dist, light_height, 0.0 } },
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

    render.populate_all_shaders(game.Game.scene) or_return

    ui.add_ui_elements(render.render_settings_ui_element, render.render_pipeline_ui_element, render.shader_store_ui_element, demo_ui_element) or_return
    ui.show_imgui_demo_window(false) or_return

    return true
}

// Example procedure you could use to query entities and modify results
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

unload_current_preview_model :: proc(arch: ^ecs.Archetype) -> (ok: bool) {
    ecs.archetype_remove_entities(arch, "demo_entity", contains_name=true) or_return
    return true
}

load_proc :: #type proc(arch: ^ecs.Archetype) -> bool
demo_ui_element : ui.UIElement : proc() -> (ok: bool) {
    im.Begin("Demo Settings")
    defer im.End()

    @(static) preview_models: []cstring = { "SciFiHelmet", "Supra", "Clearcoat Test", "Fantasy Sword" }

    @(static) load_model_procs: []load_proc
    load_model_procs = []load_proc{ load_helmet, load_supra, load_clearcoat_test, load_sword }

    @(static) selected_model_ind := 0
    if (im.BeginCombo("Preview model", preview_models[selected_model_ind])) {
        defer im.EndCombo()

        for i in 0..<len(preview_models) {
            selected := selected_model_ind == i
            if im.Selectable(preview_models[i], selected) {
                if !selected {
                    log.info("selected new preview model")
                    unload_current_preview_model(demo_arch) or_return
                    load_model_procs[i](demo_arch) or_return
                    render.populate_all_shaders(game.Game.scene) or_return
                }
                selected_model_ind = i
            }

            if selected do im.SetItemDefaultFocus()
        }
    }

    return true
}