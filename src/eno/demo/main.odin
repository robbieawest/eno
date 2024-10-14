package demo

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
    game.run_game(game_target)
}
