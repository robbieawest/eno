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

    window_target := win.initialize_window(900, 900, "eno engine demo")
    game.init_game(window_target, every_frame, before_frame); defer game.destroy_game()

    game.run_game()
}
