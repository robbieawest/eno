package game 

import SDL "vendor:sdl2"

import ecs "../ecs"
import win "../window"
import dbg "../debug"
import "../gpu"
import control "../control"

import "core:log"
import "core:os"

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
    controller: control.Controller
}

/*
    The game loop
*/
run_game :: proc() {
    Game.game_state = .RUNNING
    Game.before_frame()
    for Game.game_state == .RUNNING {
        control.poll_sdl_events(&Game.controller)
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
    Game.controller = control.init_controller(allocator)
}


init_game_default_scene :: proc(window: win.WindowTarget, every_frame: frame_loop_proc_, before_frame: before_loop_proc_, allocator := context.allocator) {
    Game = new(EnoGame, allocator)
    Game.scene = ecs.init_scene()
    Game.window = window
    Game.every_frame = every_frame
    Game.before_frame = before_frame
    Game.controller = control.init_controller(allocator)
}


destroy_game :: proc(allocator := context.allocator) {
    win.destroy_window(Game.window)
    ecs.destroy_scene(Game.scene, allocator)
    control.destroy_controller(&Game.controller)

    dbg.log_debug_stack()
    dbg.destroy_debug_stack()

    os.exit(0)
}


add_event_hooks :: proc(hooks: ..control.Hook) {
    control.add_event_hooks(&Game.controller, ..hooks)
}


add_scene_viewpoint_as_controller :: proc() {
    control.add_active_camera(&Game.controller, Game.scene.viewpoint)
}