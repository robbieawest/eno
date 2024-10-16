package demo

import SDL "vendor:sdl2"

import win "../window"
import game "../game"

import "core:log"

// Implement your before_frame and every_frame procedures in a file like this

every_frame :: proc(eno_game: ^game.EnoGame) {
    ok := win.swap_window_bufs(eno_game.window); if !ok do log.errorf("could not swap bufs")
}


before_frame :: proc(eno_game: ^game.EnoGame) {
    
    ok := game.map_sdl_events(eno_game, []game.SDLEventPair {
        { SDL.EventType.QUIT, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL event")

    ok = game.map_sdl_key_events(eno_game, []game.SDLKeyActionPair {
        { SDL.Keycode.ESCAPE, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL key event")

}
