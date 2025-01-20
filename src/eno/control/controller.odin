package control

import SDL "vendor:sdl2"

import cam "../camera"
import dbg "../debug"
import qutils "../utils/queue_utils"

import "core:container/queue"
import "../utils/queue_utils"

// This package defines functionality between input controls (keyboard, mouse etc.) and the game world
// Uses SDL events

EventType :: enum u32 {
    FIRSTEVENT,
    QUIT,
    APP_TERMINATING,
    APP_LOWMEMORY,
    APP_WILLENTERBACKGROUND,
    APP_DIDENTERBACKGROUND,
    APP_WILLENTERFOREGROUND,
    APP_DIDENTERFOREGROUND,
    LOCALECHANGED,
    DISPLAYEVENT,
    WINDOWEVENT,
    SYSWMEVENT,
    KEYDOWN,
    KEYUP,
    TEXTEDITING,
    TEXTINPUT,
    KEYMAPCHANGED,
    MOUSEMOTION,
    MOUSEBUTTONDOWN,
    MOUSEBUTTONUP,
    MOUSEWHEEL,
    JOYAXISMOTION,
    JOYBALLMOTION,
    JOYHATMOTION,
    JOYBUTTONDOWN,
    JOYBUTTONUP,
    JOYDEVICEADDED,
    JOYDEVICEREMOVED,
    CONTROLLERAXISMOTION,
    CONTROLLERBUTTONDOWN,
    CONTROLLERBUTTONUP,
    CONTROLLERDEVICEADDED,
    CONTROLLERDEVICEREMOVED,
    CONTROLLERDEVICEREMAPPED,
    CONTROLLERTOUCHPADDOWN,
    CONTROLLERTOUCHPADMOTION,
    CONTROLLERTOUCHPADUP,
    CONTROLLERSENSORUPDATE,
    FINGERDOWN,
    FINGERUP,
    FINGERMOTION,
    DOLLARGESTURE,
    DOLLARRECORD,
    MULTIGESTURE,
    CLIPBOARDUPDATE,
    DROPFILE,
    DROPTEXT,
    DROPBEGIN,
    DROPCOMPLETE,
    AUDIODEVICEADDED,
    AUDIODEVICEREMOVED,
    SENSORUPDATE,
    RENDER_TARGETS_RESET,
    RENDER_DEVICE_RESET,
    USEREVENT,
    LASTEVENT,
}

EventTypes :: bit_set[EventType]
KeyboardEvents :: EventTypes{ .KEYDOWN, .KEYUP, .TEXTEDITING, .TEXTINPUT, .KEYMAPCHANGED }


MAX_PAST_EVENTS :: 20
Controller :: struct {
    current_events: [dynamic]SDL.Event,
    past_events: queue.Queue(SDL.Event),
    global_hooks: GlobalHooks,
    camera_hooks: CameraHooks
}


action :: union #no_nil {
    empty_action,
    event_action
}

empty_action :: proc()
event_action :: proc(event: SDL.Event)

GlobalHooks :: struct {
    event_hooks: map[EventType]action,
    key_hooks: map[SDL.Keycode]action
}


camera_action :: union #no_nil {
    empty_camera_action,
    event_camera_action
}

empty_camera_action :: proc(camera: ^cam.Camera)
event_camera_action :: proc(camera: ^cam.Camera, event: SDL.Event)

CameraHooks :: struct {
    event_hooks: map[EventType]camera_action,
    key_hooks: map[SDL.Keycode]camera_action,
    active_cameras: [dynamic]^cam.Camera
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
        poll_global_hooks(controller, current_event)
        poll_key_hooks(controller, current_event)
        append(&controller.current_events, current_event)

    }

    return true
}


Hook :: union {
    EmptyGlobalHook,
    EventGlobalHook,
    EmptyKeyHook,
    EventKeyHook,

    EmptyCameraGlobalHook,
    EventCameraGlobalHook,
    EmptyCameraKeyHook,
    EventCameraKeyHook
}

EmptyGlobalHook :: GlobalHook(empty_action)
EventGlobalHook :: GlobalHook(event_action)
EmptyKeyHook :: KeyHook(empty_action)
EventKeyHook :: KeyHook(event_action)

EmptyCameraGlobalHook :: GlobalHook(empty_camera_action)
EventCameraGlobalHook :: GlobalHook(event_camera_action)
EmptyCameraKeyHook :: KeyHook(empty_camera_action)
EventCameraKeyHook :: KeyHook(event_camera_action)


GlobalHook :: struct($proc_type: typeid)
    where
        proc_type == empty_action           ||
        proc_type == event_action           ||
        proc_type == empty_camera_action    ||
        proc_type == event_camera_action
{
    event_type: EventType,
    action: proc_type
}

KeyHook :: struct($proc_type: typeid)
    where
        proc_type == empty_action           ||
        proc_type == event_action           ||
        proc_type == empty_camera_action    ||
        proc_type == event_camera_action
{
    key: SDL.Keycode,
    action: proc_type
}


add_event_hooks :: proc(controller: ^Controller, hooks: ..Hook) {
    for hook in hooks {
        switch v in hook {
        case EventGlobalHook:
            controller.global_hooks.event_hooks[v.event_type] = v.action
        case EmptyGlobalHook:
            controller.global_hooks.event_hooks[v.event_type] = v.action

        case EmptyKeyHook:
            controller.global_hooks.key_hooks[v.key] = v.action
        case EventKeyHook:
            controller.global_hooks.key_hooks[v.key] = v.action

        case EmptyCameraGlobalHook:
            controller.camera_hooks.event_hooks[v.event_type] = v.action
        case EventCameraGlobalHook:
            controller.camera_hooks.event_hooks[v.event_type] = v.action

        case EmptyCameraKeyHook:
            controller.camera_hooks.key_hooks[v.key] = v.action
        case EventCameraKeyHook:
            controller.camera_hooks.key_hooks[v.key] = v.action
        }
    }
}

poll_global_hooks :: proc(controller: ^Controller, event: SDL.Event) {
    action, action_exists := controller.global_hooks.event_hooks[cast(EventType)event.type]
    if action_exists {
        switch act in action {
            case empty_action: act()
            case event_action: act(event)
        }
    }
}



poll_key_hooks :: proc(controller: ^Controller, event: SDL.Event) {
    if cast(EventType)(event.type) not_in KeyboardEvents do return

    action, action_exists := controller.global_hooks.key_hooks[event.key.keysym.sym]
    if action_exists {
        switch act in action {
        case empty_action: act()
        case event_action: act(event)
        }
    }
}