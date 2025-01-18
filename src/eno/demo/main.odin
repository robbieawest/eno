package demo

import win "../window"
import game "../game"

import "core:log"

main :: proc() {
    context.logger = log.create_console_logger()
    log.info("Starting Demo")

    window_target := win.initialize_window(900, 900, "eno engine demo")
    game.init_game(window_target, every_frame, before_frame); defer game.destroy_game()

    game.run_game()
}
