package demo

import "core:log"
import win "../window"
import game "../game"

every_frame :: proc(eno_game: ^game.EnoGame) {
    ok := win.swap_window_bufs(eno_game.window); if !ok do log.errorf("could not swap bufs")
}
