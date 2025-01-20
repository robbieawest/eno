package control

import SDL "vendor:sdl2"

import cam "../camera"
import dbg "../debug"
import qutils "../utils/queue_utils"

import "core:container/queue"
import "../utils/queue_utils"

// This package defines functionality between input controls (keyboard, mouse etc.) and the game world
// Uses SDL events


MAX_PAST_EVENTS :: 20
Controller :: struct {
    current_events: [dynamic]SDL.Event,
    past_events: queue.Queue(SDL.Event),
    global_hooks: GlobalHooks
}

hook :: #type proc()
GlobalHooks :: struct {
    event_hooks: map[SDL.EventType]hook,
    key_hooks: map[SDL.Keycode]hook
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

    push_front_err := qutils.push_front_elems(&controller.past_events, ..controller.current_events[:])
    if push_front_err != .None {
        queue_utils.handle_queue_error(push_front_err)
        return
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


poll_sdl_events :: proc(controller: ^Controller) -> (ok: bool) {
    save_current_events(controller)
    clear_current_events(controller)

    current_event: SDL.Event
    for SDL.PollEvent(&current_event) {
        poll_global_hooks(controller, current_event.type)
        poll_key_hooks(controller, current_event.key.keysym.sym)
        append(&controller.current_events, current_event)

    }

    return true
}


EventHook :: union {
    GlobalHook, KeyHook
}

GlobalHook :: struct {
    event_type: SDL.EventType,
    action: hook
}

KeyHook :: struct {
    key: SDL.Keycode,
    action: hook
}

add_event_hooks :: proc(controller: ^Controller, hooks: ..EventHook) {
    for hook in hooks {
        switch v in hook {
        case GlobalHook:
            controller.global_hooks.event_hooks[v.event_type] = v.action
        case KeyHook:
            controller.global_hooks.key_hooks[v.key] = v.action
        }
    }
}


poll_global_hooks :: proc(controller: ^Controller, event_type: SDL.EventType) {
    action, action_exists := controller.global_hooks.event_hooks[event_type]
    if action_exists do action()
}

poll_key_hooks :: proc(controller: ^Controller, key: SDL.Keycode) {
    action, action_exists := controller.global_hooks.key_hooks[key]
    if action_exists do action()
}
