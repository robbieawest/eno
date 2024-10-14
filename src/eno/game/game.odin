package game 

import ecs "../ecs"
import win "../window"
import "core:log"

// Game structure is defined here, e.g. defining the game loop, polling events, etc.

frame_loop_proc_ :: proc(game: ^EnoGame) // Defines type for the procedure called every frame


GAME_STATE :: enum { NOT_STARTED, RUNNING, HALTED, QUIT }


EnoGame :: struct {
    window: win.WindowTarget,
    scene: ^ecs.Scene, // Defined as a single scene per game, this obviously needs some sort of change, since games do not only have a single scene,
    every_frame: frame_loop_proc_,
    game_state: GAME_STATE
}


run_game :: proc(game: ^EnoGame) {
    game.game_state = .RUNNING
    for game.game_state == .RUNNING {
        // poll some events
        game.every_frame(game)
    }
}


halt_game :: proc(game: ^EnoGame) {
    game.game_state = .HALTED
}


quit_game :: proc(game: ^EnoGame) {
    game.game_state = .QUIT
}


init_game :: proc { init_game_with_scene, init_game_default_scene }


init_game_with_scene :: proc(scene: ^ecs.Scene, window: win.WindowTarget, every_frame: frame_loop_proc_) -> (game: ^EnoGame) {
    game = new(EnoGame)
    game.scene = scene
    game.window = window
    game.every_frame = every_frame
    return game
}


init_game_default_scene :: proc(window: win.WindowTarget, every_frame: frame_loop_proc_) -> (game: ^EnoGame) {
    game = new(EnoGame)
    game.scene = ecs.init_scene_empty()
    game.window = window
    game.every_frame = every_frame
    return game
}


destroy_game :: proc(game: ^EnoGame) {
    win.destroy_window(game.window)
    ecs.destroy_scene(game.scene)
    free(game)
}
