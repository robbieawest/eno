package demo

import win "../window"
import game "../game"
import dbg "../debug"

import "core:log"
import "core:testing"

main :: proc() {
    logger, logger_ok := dbg.init_logger()
    if !logger_ok do return
    context.logger = logger

    log.info("Starting Demo")

    window_target, win_ok := win.initialize_window(1440, 1080, "eno engine demo")
    if !win_ok do return
    // win.set_fullscreen(window_target)
    win.set_mouse_raw_input(true)

    if(!game.init_game(window_target, every_frame, before_frame)) {
        log.error("Could not start game")
        return
    }
    defer game.destroy_game()

    game.run_game()
}

@(test)
test_main :: proc(t: ^testing.T) {
    main()
}