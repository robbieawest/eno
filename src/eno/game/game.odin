package game 

import SDL "vendor:sdl2"

import ecs "../ecs"
import win "../window"

import "core:log"

// Game structure is defined here, e.g. defining the game loop, polling events, etc.

// Procedure type definitions
frame_loop_proc_ :: proc(game: ^EnoGame) // For the procedure that executes every frame
event_action_proc_ :: proc(game: ^EnoGame)


GAME_STATE :: enum { NOT_STARTED, RUNNING, HALTED, QUIT }


EnoGame :: struct {
    window: win.WindowTarget,
    scene: ^ecs.Scene, // Defined as a single scene per game, this obviously needs some sort of change, since games do not only have a single scene,
    every_frame: frame_loop_proc_,
    game_state: GAME_STATE,
    sdl_event_map: map[SDL.EventType]event_action_proc_,
    sdl_key_map: map[SDL.Keycode]event_action_proc_
}


run_game :: proc(game: ^EnoGame) {
    game.game_state = .RUNNING
    for game.game_state == .RUNNING {
        poll_sdl_events(game)
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

// Events

@(private)
poll_sdl_events :: proc(game: ^EnoGame) -> (ok: bool) {
    if win.CURRENT_WINDOWER != .SDL do return ok

    current_sdl_event: SDL.Event
    for SDL.PollEvent(&current_sdl_event) {
        event_type := current_sdl_event.type
        action, action_found := game.sdl_event_map[event_type]
        if action_found do action(game)
        
        if event_type == .KEYDOWN {
            key_code := current_sdl_event.key.keysym.sym
            key_action, key_action_found := game.sdl_key_map[key_code]
            if key_action_found do key_action(game)
        }
    }

    return true
}

SDLEventPair :: struct {
    event: SDL.EventType,
    action: event_action_proc_
}


SDLKeyActionPair :: struct {
    key: SDL.Keycode,
    action: event_action_proc_
}


map_sdl_events :: proc(game: ^EnoGame, event_pairs: []SDLEventPair) -> (ok: bool) {
    if win.CURRENT_WINDOWER != .SDL do return ok
    for event_pair in event_pairs do ok |= map_sdl_event(game, event_pair) // Error propogates through
    return true
}

@(private)
map_sdl_event :: proc(game: ^EnoGame, event_pair: SDLEventPair) -> (ok: bool) {
    if event_pair.event in game.sdl_event_map do return ok
    game.sdl_event_map[event_pair.event] = event_pair.action
    return true
}


map_sdl_key_events :: proc(game: ^EnoGame, key_pairs: []SDLKeyActionPair) -> (ok: bool) {
    if win.CURRENT_WINDOWER != .SDL do return ok
    for key_pair in key_pairs do ok |= map_sdl_key_event(game, key_pair) // Error propogates through
    return true
}

@(private)
map_sdl_key_event :: proc(game: ^EnoGame, key_pair: SDLKeyActionPair) -> (ok: bool) {
    if key_pair.key in game.sdl_key_map do return ok
    game.sdl_key_map[key_pair.key] = key_pair.action
    return true
}
