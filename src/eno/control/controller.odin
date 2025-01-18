package control

import SDL "vendor:sdl2"

import cam "../camera"
import dbg "../debug"
import qutils "../utils."

import "core:container/queue"
import "../utils/queue_utils"

// This package defines functionality between input controls (keyboard, mouse etc.) and the game world
// Uses SDL events


// Holds currently activated controls
// Holds past activated controls

MAX_PAST_EVENTS :: 20
Controller :: struct {
    current_events: [dynamic]SDL.Event,
    past_events: queue.Queue(SDL.Event)
}


init_controller :: proc(allocator := context.allocator) -> (controller: Controller) {
    queue.init(&controller.past_events, MAX_PAST_EVENTS, allocator)
    make_current_events(&controller)
    return
}

// Allocators are stored internally in the structures
destroy_controller :: proc(controller: ^Controller) {
    queue.destroy(&controller.past_events)
    delete(controller.current_events)
}


@(private)
make_current_events :: proc(controller: ^Controller, allocator := context.allocator) {
    controller.current_events = make([dynamic]SDL.Event, 0, 1, allocator)
}


@(private)
save_current_events :: proc(controller: ^Controller) -> (ok: bool) {
    n_Overflow := len(controller.current_events) - queue.space(controller.past_events)
    if n_Overflow > 0 {
        rem_err := qutils.remove_back_n_elems(&controller.past_events, n_Overflow)
        if rem_err != .None {
            queue_utils.handle_queue_error(rem_err)
            return
        }
    }

    for event in controller.current_events {
        queue.p
    }

    ok = true
    return
}


@(private)
clear_current_events :: proc(controller: ^Controller, allocator := context.allocator) {
    delete(controller.current_events)
    make_current_events(controller, allocator)
}


set_number_of_past_events :: proc(controller: ^Controller, cap: int) {
    queue.reserve(&controller.past_events, cap)
}


poll_sdl_events :: proc() -> (ok: bool) {

    current_event: SDL.Event
    for SDL.PollEvent(&current_event) {

    }

    return true
}
