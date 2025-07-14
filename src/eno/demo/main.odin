package demo

import win "../window"
import game "../game"

import "core:log"
import "core:testing"

main :: proc() {

    context.logger = log.create_console_logger()
    log.info("Starting Demo")

    window_target := win.initialize_window(900, 900, "eno engine demo")
    // win.set_fullscreen(window_target)
    win.set_mouse_relative_mode(true)
    win.set_mouse_raw_input(true)

    game.init_game(window_target, every_frame, before_frame); defer game.destroy_game()

    game.run_game()
}

@(test)
test_main :: proc(t: ^testing.T) {
    main()
}