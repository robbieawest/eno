package game 

import SDL "vendor:sdl2"

import ecs "../ecs"
import "../resource"
import win "../window"
import dbg "../debug"
import "../control"
import "../camera"
import "../ui"

import glm "core:math/linalg/glsl"
import "core:time"
import render "../render"

// Game structure is defined here, e.g. defining the game loop, polling events, etc.

// Procedure type definitions
frame_loop_proc_ :: proc() -> (ok: bool) // For the procedure that executes every frame
before_loop_proc_ :: proc() -> (ok: bool)


GAME_STATE :: enum { NOT_STARTED, RUNNING, HALTED, QUIT }

Game: ^EnoGame
EnoGame :: struct {
    window: win.WindowTarget,
    scene: ^ecs.Scene, // Defined as a single scene per game
    every_frame: frame_loop_proc_,
    before_frame: before_loop_proc_,
    state: GAME_STATE,
    game_data: rawptr, // Use to store arbitrary information, for example render pipelines between before_frame and every_frame calls
    controller: control.Controller,
    resource_manager: resource.ResourceManager,
    meta_data: GameMetaData
}

/*
    The game loop
*/
run_game :: proc() {
    if Game == nil {
        dbg.log(.ERROR, "Game not initialized")
        return
    }

    Game.state = .RUNNING

    before_ok := Game.before_frame()
    if !before_ok {
        dbg.log(.ERROR, "False received from before_frame procedure. Terminating")
        return
    }
    else {
        dbg.log(.INFO, "before_frame complete, moving to loop")
    }

    for Game.state == .RUNNING {
        t_before_frame := time.now()._nsec

        control.poll(&Game.controller)
        // glutils.frame_setup()

        every_ok := Game.every_frame()

        if !every_ok {
            dbg.log(.ERROR, "False received from every_frame procedure. Terminating")
            return
        }

        Game.meta_data.last_delta = time.now()._nsec - t_before_frame
        update_metadata_elapsed(&Game.meta_data)
        // dbg.log(.INFO, "Frame time: %.2f", f32(Game.meta_data.last_delta) / 1_000_000)

        resource.clear_unused_resources(&Game.resource_manager) // todo handle bool ret
    }

}


halt_game :: proc() {
    Game.state = .HALTED
}


quit_game :: proc() {
    Game.state = .QUIT
}


init_game :: proc { init_game_with_scene, init_game_default_scene }


init_game_with_scene :: proc(scene: ^ecs.Scene, window: win.WindowTarget, every_frame: frame_loop_proc_, before_frame: before_loop_proc_, allocator := context.allocator) -> (ok: bool) {
    Game = new(EnoGame, allocator)
    Game.scene = scene
    Game.window = window
    Game.every_frame = every_frame
    Game.before_frame = before_frame
    Game.controller = control.init_controller(allocator)
    Game.resource_manager = resource.init_resource_manager(allocator)
    Game.meta_data.time_started = time.now()._nsec

    ui.add_ui_elements(render.render_settings_ui_element) or_return
    return true
}


init_game_default_scene :: proc(window: win.WindowTarget, every_frame: frame_loop_proc_, before_frame: before_loop_proc_, allocator := context.allocator) -> (ok: bool) {
    return init_game_with_scene(ecs.init_scene(), window, every_frame, before_frame, allocator)
}

destroy_game :: proc(allocator := context.allocator) {
    resource.destroy_manager(&Game.resource_manager)
    ecs.destroy_scene(Game.scene, allocator)
    control.destroy_controller(&Game.controller)
    win.destroy_window(Game.window)

    dbg.log_debug_stack()
    dbg.destroy_debug_stack()
}


add_event_hooks :: proc(hooks: ..control.HookInput) {
    control.add_hooks(&Game.controller, ..hooks)
}


scene_viewpoint :: proc() -> ^camera.Camera {
    return Game.scene.viewpoint
}


get_mouse_speed_unscaled :: proc() -> f32 {
    return Game.controller.mouse_settings.mouse_speed
}

get_mouse_speed :: proc() -> f32 {
    return Game.controller.mouse_settings.mouse_speed * control.MOUSE_SPEED_SCALING
}


scale_mouse_relative :: proc(xrel: f32, yrel: f32) -> (xout: f32, yout: f32) {
    scaling := Game.controller.mouse_settings.mouse_speed * control.MOUSE_SPEED_SCALING
    xout = xrel * scaling
    yout = yrel * scaling
    return
}


HOOKS_CAMERA_MOVEMENT :: proc() -> (hooks: control.Hooks) {
    viewpoint := Game.scene.viewpoint
    if viewpoint == nil {
        dbg.log(.INFO, "Cannot add camera hooks without scene viewpoint")
        return
    }

    hooks = make([dynamic]control.Hook)
    append_elems(&hooks,
        control.make_hook(
            control.make_hook_identifier(key_states = []SDL.Scancode{ .W }),
            proc(_: ^SDL.Event, cam_data: rawptr) { camera.move_with_yaw(cast(^camera.Camera)cam_data, glm.vec3{ 0.0, 0.0, -1.0 }, Game.meta_data.last_delta) },
            viewpoint
        ),
        control.make_hook(
            control.make_hook_identifier(key_states = []SDL.Scancode{ .A }),
            proc(_: ^SDL.Event, cam_data: rawptr) { camera.move_with_yaw(cast(^camera.Camera)cam_data, glm.vec3{ -1.0, 0.0, 0.0 }, Game.meta_data.last_delta) },
            viewpoint
        ),
        control.make_hook(
            control.make_hook_identifier(key_states = []SDL.Scancode{ .S }),
            proc(_: ^SDL.Event, cam_data: rawptr) { camera.move_with_yaw(cast(^camera.Camera)cam_data, glm.vec3{ 0.0, 0.0, 1.0 }, Game.meta_data.last_delta) },
            viewpoint
        ),
        control.make_hook(
            control.make_hook_identifier(key_states = []SDL.Scancode{ .D }),
            proc(_: ^SDL.Event, cam_data: rawptr) { camera.move_with_yaw(cast(^camera.Camera)cam_data, glm.vec3{ 1.0, 0.0, 0.0 }, Game.meta_data.last_delta) },
            viewpoint
        ),
        control.make_hook(
            control.make_hook_identifier(key_states = []SDL.Scancode{ .SPACE }),
            proc(_: ^SDL.Event, cam_data: rawptr) { camera.move_with_yaw(cast(^camera.Camera)cam_data, glm.vec3{ 0.0, 1.0, 0.0 }, Game.meta_data.last_delta) },
            viewpoint
        ),
        control.make_hook(
            control.make_hook_identifier(key_states = []SDL.Scancode{ .LCTRL }),
            proc(_: ^SDL.Event, cam_data: rawptr) { camera.move_with_yaw(cast(^camera.Camera)cam_data, glm.vec3{ 0.0, -1.0, 0.0 }, Game.meta_data.last_delta) },
            viewpoint
        ),
    )
    return
}

HOOK_MOUSE_MOTION :: proc() -> (hooks: control.Hooks) {
    hooks = make(control.Hooks)
    append(&hooks,
        control.make_hook(
            control.make_hook_identifier(event_types = []SDL.EventType{ .MOUSEMOTION }),
            proc(event: ^SDL.Event, cam_data: rawptr) {
                if Game.controller.mouse_settings.mouse_enabled {
                    xrel, yrel := scale_mouse_relative(f32(event.motion.xrel), f32(event.motion.yrel))
                    // dbg.log(.INFO, "Mouse motion x: %f, y: %f", xrel, yrel)
                    control.direct_camera(cast(^camera.Camera)cam_data, xrel, yrel)
                }
            },
            scene_viewpoint()
        ),
    )
    return
}

HOOK_CLOSE_WINDOW :: proc() -> (hooks: control.Hooks) {
    hooks = make(control.Hooks)
    append(&hooks,
        control.make_hook(
            control.make_hook_identifier(event_types = []SDL.EventType{ .QUIT }, event_keys = []SDL.Scancode{ .ESCAPE }),
            proc(_: ^SDL.Event, _: rawptr) { quit_game() },
            nil
        )
    )
    return
}

HOOK_TOGGLE_UI_MOUSE :: proc() -> (hooks: control.Hooks) {
    hooks = make(control.Hooks)
    append(&hooks,
        control.make_hook(
            control.make_hook_identifier(event_types = []SDL.EventType{ .KEYDOWN } ),
            proc(event: ^SDL.Event, _: rawptr) {
                if event.key.keysym.scancode == .M {
                    win.toggle_mouse_relative_mode(); ui.toggle_mouse_usage()
                    control.toggle_mouse_enabled(&Game.controller)
                }
            },
            nil
        )
    )
    return
}

GameMetaData :: struct {
    time_elapsed: i64,
    time_started: i64,
    last_delta: i64
}

update_metadata_elapsed :: proc(metadata: ^GameMetaData) {
    metadata.time_elapsed = time.now()._nsec - metadata.time_started
}