package demo

import SDL "vendor:sdl2"

import win "../window"
import ecs "../ecs"
import gpu "../gpu"
import model "../model"
import game "../game"

import "core:log"
import "core:fmt"

main :: proc() {
    context.logger = log.create_console_logger()
    log.info("Starting Demo")

    window_target, ok := win.initialize_window(900, 900, "eno engine demo"); if !ok do return
    game_target := game.init_game(window_target, every_frame); defer game.destroy_game(game_target)

    ok = game.map_sdl_events(game_target, []game.SDLEventPair {
        { SDL.EventType.QUIT, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL event")

    ok = game.map_sdl_key_events(game_target, []game.SDLKeyActionPair {
        { SDL.Keycode.ESCAPE, proc(g: ^game.EnoGame) { game.quit_game(g) }}
    }); if !ok do log.errorf("Could not map SDL key event")

    game.run_game(game_target)
}
