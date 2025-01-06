package game 

import SDL "vendor:sdl2"

import ecs "../ecs"
import win "../window"
import dbg "../debug"

import "core:log"
import "core:os"

// Game structure is defined here, e.g. defining the game loop, polling events, etc.

// Procedure type definitions
frame_loop_proc_ :: proc() // For the procedure that executes every frame
event_action_proc_ :: proc()
before_loop_proc_ :: proc()


GAME_STATE :: enum { NOT_STARTED, RUNNING, HALTED, QUIT }

Game: ^EnoGame
EnoGame :: struct {
    window: win.WindowTarget,
    scene: ^ecs.Scene, // Defined as a single scene per game, this obviously needs some sort of change, since games do not only have a single scene,
    every_frame: frame_loop_proc_,
    before_frame: before_loop_proc_,
    game_state: GAME_STATE,
    sdl_event_map: map[SDL.EventType]event_action_proc_,
    sdl_key_map: map[SDL.Keycode]event_action_proc_,
}


run_game :: proc() {
    Game.game_state = .RUNNING
    Game.before_frame()
    for Game.game_state == .RUNNING {
        poll_sdl_events()
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


init_game_with_scene :: proc(scene: ^ecs.Scene, window: win.WindowTarget, every_frame: frame_loop_proc_, before_frame: before_loop_proc_) {
    Game = new(EnoGame)
    Game.scene = scene
    Game.window = window
    Game.every_frame = every_frame
    Game.before_frame = before_frame
}


init_game_default_scene :: proc(window: win.WindowTarget, every_frame: frame_loop_proc_, before_frame: before_loop_proc_) {
    Game = new(EnoGame)
    Game.scene = ecs.init_scene()
    Game.window = window
    Game.every_frame = every_frame
    Game.before_frame = before_frame
}


destroy_game :: proc() {
    win.destroy_window(Game.window)
    ecs.destroy_scene(Game.scene)
    dbg.destroy_debug_stack() // heap corruption

    log.info("here")
    free_all(context.allocator)
    free_all(context.temp_allocator)
    os.exit(0)
}

// Events

@(private)
poll_sdl_events :: proc() -> (ok: bool) {
    if win.CURRENT_WINDOWER != .SDL do return ok

    current_sdl_event: SDL.Event
    for SDL.PollEvent(&current_sdl_event) {
        event_type := current_sdl_event.type
        action, action_found := Game.sdl_event_map[event_type]
        if action_found do action()
        
        if event_type == .KEYDOWN {
            key_code := current_sdl_event.key.keysym.sym
            key_action, key_action_found := Game.sdl_key_map[key_code]
            if key_action_found do key_action()
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


map_sdl_events :: proc(event_pairs: []SDLEventPair) -> (ok: bool) {
    if win.CURRENT_WINDOWER != .SDL do return ok
    for event_pair in event_pairs do ok |= map_sdl_event(event_pair) // Error propogates through
    return true
}

@(private)
map_sdl_event :: proc(event_pair: SDLEventPair) -> (ok: bool) {
    if event_pair.event in Game.sdl_event_map do return ok
    Game.sdl_event_map[event_pair.event] = event_pair.action
    return true
}


map_sdl_key_events :: proc(key_pairs: []SDLKeyActionPair) -> (ok: bool) {
    if win.CURRENT_WINDOWER != .SDL do return ok
    for key_pair in key_pairs do ok |= map_sdl_key_event(key_pair) // Error propogates through
    return true
}

@(private)
map_sdl_key_event :: proc(key_pair: SDLKeyActionPair) -> (ok: bool) {
    if key_pair.key in Game.sdl_key_map do return ok
    Game.sdl_key_map[key_pair.key] = key_pair.action
    return true
}
