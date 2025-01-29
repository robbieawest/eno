package game 

import SDL "vendor:sdl2"

import ecs "../ecs"
import win "../window"
import dbg "../debug"
import "../gpu"
import control "../control"
import control2 "../control2"

import "core:log"
import "core:os"
import "../camera"

// Game structure is defined here, e.g. defining the game loop, polling events, etc.

// Procedure type definitions
frame_loop_proc_ :: proc() // For the procedure that executes every frame
before_loop_proc_ :: proc()


GAME_STATE :: enum { NOT_STARTED, RUNNING, HALTED, QUIT }

Game: ^EnoGame
EnoGame :: struct {
    window: win.WindowTarget,
    scene: ^ecs.Scene, // Defined as a single scene per game, this obviously needs some sort of change, since games do not only have a single scene,
    every_frame: frame_loop_proc_,
    before_frame: before_loop_proc_,
    game_state: GAME_STATE,
    controller: control2.Controller
}

/*
    The game loop
*/
run_game :: proc() {
    Game.game_state = .RUNNING
    Game.before_frame()
    for Game.game_state == .RUNNING {
        control2.poll(&Game.controller)
        gpu.frame_setup()
        Game.every_frame()
    }
}


halt_game :: proc() {
    Game.game_state = .HALTED
}


quit_game :: proc() {
    Game.game_state = .QUIT
}


init_game :: proc { init_game_with_scene, init_game_default_scene }


init_game_with_scene :: proc(scene: ^ecs.Scene, window: win.WindowTarget, every_frame: frame_loop_proc_, before_frame: before_loop_proc_, allocator := context.allocator) {
    Game = new(EnoGame, allocator)
    Game.scene = scene
    Game.window = window
    Game.every_frame = every_frame
    Game.before_frame = before_frame
    Game.controller = control2.init_controller(allocator)
}


init_game_default_scene :: proc(window: win.WindowTarget, every_frame: frame_loop_proc_, before_frame: before_loop_proc_, allocator := context.allocator) {
    Game = new(EnoGame, allocator)
    Game.scene = ecs.init_scene()
    Game.window = window
    Game.every_frame = every_frame
    Game.before_frame = before_frame
    Game.controller = control2.init_controller(allocator)
}


destroy_game :: proc(allocator := context.allocator) {
    win.destroy_window(Game.window)
    ecs.destroy_scene(Game.scene, allocator)
    control2.destroy_controller(&Game.controller)

    dbg.log_debug_stack()
    dbg.destroy_debug_stack()

    os.exit(0)
}


add_event_hooks :: proc(hooks: ..control2.Hook) {
    append_elems(&Game.controller.hooks, ..hooks)
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