package control2

import SDL "vendor:sdl2"

import cam "../camera"
import qutils "../utils/queue_utils"

import "core:container/queue"
import glm "core:math/linalg/glsl"
import "core:slice"


MAX_PAST_EVENTS :: 20
Controller :: struct {
    current_events: [dynamic]SDL.Event,
    past_events: queue.Queue(SDL.Event),
    mouse_settings: MouseSettings,
    hooks: Hooks
}

Hooks :: [dynamic]Hook


init_controller :: proc(allocator := context.allocator) -> (controller: Controller) {
    queue.init(&controller.past_events, MAX_PAST_EVENTS, allocator)
    make_current_events(&controller)
    controller.mouse_settings = init_mouse_settings()
    return
}

// Allocators are stored internally in the structures
destroy_controller :: proc(controller: ^Controller) {
    queue.destroy(&controller.past_events)
    for &hook in controller.hooks do destroy_hook(&hook)
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
            qutils.handle_queue_error(rem_err)
            return
        }
    }

    push_front_err := qutils.push_front_elems(&controller.past_events, ..controller.current_events[:])
    if push_front_err != .None {
        qutils.handle_queue_error(push_front_err)
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


// Mouse

MouseSettings :: struct {
    mouse_speed: f32
}
DEFAULT_MOUSE_SPEED : f32 : 1.0
MOUSE_SPEED_SCALING : f32 : 0.1


init_mouse_settings :: proc(mouse_speed := DEFAULT_MOUSE_SPEED) -> MouseSettings {
    return { mouse_speed = mouse_speed }
}

set_mouse_speed :: proc(controller: ^Controller, mouse_speed := DEFAULT_MOUSE_SPEED) {
    controller.mouse_settings.mouse_speed = mouse_speed
}

/*
    Right handed
    yaw axis (0, -1, 0)
    pitch axis (-1, 0, 0)

    if only the bloody engineers found a standard for this I wouldn't have to create arbitrary axis'
*/
direct_camera :: proc(camera: ^cam.Camera, xrel: f32, yrel: f32) {
    camera.yaw += xrel
    camera.pitch -= yrel

    // Constrain
    camera.pitch = max(-89.0, camera.pitch)
    camera.pitch = min(89.0, camera.pitch)

    // Euler rotation
    yaw := glm.radians(camera.yaw)
    pitch := glm.radians(camera.pitch)

    camera.towards.x = glm.cos(yaw) * glm.cos(pitch)
    camera.towards.y = glm.sin(pitch)
    camera.towards.z = glm.sin(yaw) * glm.cos(pitch)

    camera.towards = glm.normalize(camera.towards)
}


// Actions and hooks

Hook :: struct {
    identifier: HookIdentifier,
    action: Action
}

destroy_hook :: proc(hook: ^Hook) {
    destroy_hook_identifier(&hook.identifier)
}

Action :: #type proc(event: ^SDL.Event, data: rawptr)

HookIdentifier :: struct {
    event_type_mask: u32,
    event_keys: [dynamic] SDL.Scancode,  // For keys pressed in an event
    key_state: [dynamic] SDL.Scancode, // For keyboard state - not directly tied to events
    mouse_button_mask: i32     // For mouse states - not directly tied to events
}

/*
    Construct a hook identifier from properties which you want the hook to be activated on
    Use the add and remove procedrues to directly update a hook identifier
*/
make_hook_identifier :: proc(event_types: []SDL.EventType, key_codes: []SDL.Scancode, key_states: []SDL.Scancode, mouse_buttons: []i32) -> (ident: HookIdentifier) {
    for type in event_types do add_event_type(&ident, type)
    for button in mouse_buttons do add_mouse_button(&ident, button)
    ident.event_keys = slice.clone_to_dynamic(key_codes)
    ident.key_state = slice.clone_to_dynamic(key_states)

    return
}

destroy_hook_identifier :: proc(ident: ^HookIdentifier) {
    delete(ident.key_state)
    delete(ident.event_keys)
}


add_event_type :: proc(ident: ^HookIdentifier, type: SDL.EventType) {
    ident.event_type_mask |= u32(type)
}

remove_event_type :: proc(ident: ^HookIdentifier, type: SDL.EventType) {
    ident.event_type_mask &~= u32(type)
}

add_mouse_button :: proc(ident: ^HookIdentifier, button: i32) {
    ident.mouse_button_mask |= button
}

remove_mouse_button :: proc(ident: ^HookIdentifier, button: i32) {
    ident.mouse_button_mask &~= button
}

add_key_code :: proc(ident: ^HookIdentifier, code: SDL.Keycode) {
    append(&ident.event_keys, code)
}

add_key_state :: proc(ident: ^HookIdentifier, scancode: SDL.Scancode) {
    append(&ident.key_state, scancode)
}


add_hook :: proc(controller: ^Controller, ident: HookIdentifier, action: Action) {
    append(&controller.hooks, Hook{ ident, action })
}

/*
    Polls SDL for events
    Checks states

    Makes sure that for each hook the action is called at most one time throughout the procedure
*/
poll :: proc(controller: ^Controller) {

    activated := make([dynamic]^Hook, 0); defer delete(activated)  // make into a hashset

    current_event: ^SDL.Event
    for SDL.PollEvent(current_event) {
        if current_event == nil do continue

        for &hook in controller.hooks {
            if u32(current_event.type) | hook.identifier.event_type_mask != 0 || slice.contains(hook.identifier.event_keys[:], current_event.key.keysym.scancode) {
                append(&activated, &hook)
                break
            }

        }
    }
}