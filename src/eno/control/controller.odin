package control

import SDL "vendor:sdl2"

import cam "../camera"
import dbg "../debug"
import qutils "../utils/queue_utils"

import "core:container/queue"
import "../utils/queue_utils"
import "core:reflect"
import glm "core:math/linalg/glsl"

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

conv_event_type :: proc(type: SDL.EventType) -> (conv: EventType) {
    name, ok := reflect.enum_name_from_value(type); if !ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "Could not convert enum")
        return
    }
    conv, ok = reflect.enum_from_name(EventType, name); if !ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "Could not convert enum")
    }
    return
}

EventTypes :: bit_set[EventType]
KeyboardEvents :: EventTypes{ .KEYDOWN, .KEYUP, .TEXTEDITING, .TEXTINPUT, .KEYMAPCHANGED }


MAX_PAST_EVENTS :: 20
Controller :: struct {
    current_events: [dynamic]SDL.Event,
    past_events: queue.Queue(SDL.Event),
    global_hooks: GlobalHooks,
    camera_hooks: CameraHooks,
    mouse_settings: MouseSettings,
    states: State,
    state_hooks: StateHooks
}


Action :: union #no_nil {
    empty_action,
    event_action
}

empty_action :: proc()
event_action :: proc(event: SDL.Event)

GlobalHooks :: struct {
    event_hooks: map[EventType]Action,
    key_hooks: map[SDL.Keycode]Action,
    state_hooks: StateHooks
}


CameraAction :: union #no_nil {
    empty_camera_action,
    event_camera_action
}

empty_camera_action :: proc(camera: ^cam.Camera)
event_camera_action :: proc(camera: ^cam.Camera, event: SDL.Event)

CameraHooks :: struct {
    event_hooks: map[EventType]CameraAction,
    key_hooks: map[SDL.Keycode]CameraAction,
    active_cameras: [dynamic]^cam.Camera
}


init_controller :: proc(allocator := context.allocator) -> (controller: Controller) {
    queue.init(&controller.past_events, MAX_PAST_EVENTS, allocator)
    make_current_events(&controller)
    controller.mouse_settings = init_mouse_settings()
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
        type := conv_event_type(current_event.type)
        poll_global_hooks(controller, type, current_event)
        poll_key_hooks(controller, type, current_event)
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

poll_global_hooks :: proc(controller: ^Controller, type: EventType, event: SDL.Event) {
    action, action_exists := controller.global_hooks.event_hooks[type]
    if action_exists do handle_action(action, event)

    camera_action, camera_action_exists := controller.camera_hooks.event_hooks[type]
    if camera_action_exists do handle_camera_action(controller, camera_action, event)
}


poll_key_hooks :: proc(controller: ^Controller, type: EventType, event: SDL.Event) {
    if type not_in KeyboardEvents do return

    action, action_exists := controller.global_hooks.key_hooks[event.key.keysym.sym]
    if action_exists do handle_action(action, event)

    camera_action, camera_action_exists := controller.camera_hooks.key_hooks[event.key.keysym.sym]
    if camera_action_exists do handle_camera_action(controller, camera_action, event)
}


@(private)
handle_action :: proc(action: Action, event: SDL.Event) {
    switch act in action {
        case empty_action: act()
        case event_action: act(event)
    }
}

@(private)
handle_camera_action :: proc(controller: ^Controller, camera_action: CameraAction, event: SDL.Event) {
    switch act in camera_action {
        case empty_camera_action: for &active_camera in controller.camera_hooks.active_cameras do act(active_camera)
        case event_camera_action: for &active_camera in controller.camera_hooks.active_cameras do act(active_camera, event)
    }
}


add_active_camera :: proc(controller: ^Controller, camera: ^cam.Camera) {
    append(&controller.camera_hooks.active_cameras, camera)
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


// Handling states

State :: struct {
    keyboard_state: KeyboardState,
    mouse_state: MouseState,
}

Button :: enum u8 {
    BUTTON_LEFT,
    BUTTON_MIDDLE,
    BUTTON_RIGHT,
    BUTTON_X1,
    BUTTON_X2
}

MouseState :: bit_set[Button]

KeyboardState :: []SDL.Scancode

get_states :: proc(state: ^State) {
    state.keyboard_state = transmute(KeyboardState) SDL.GetKeyboardStateAsSlice()

    x: i32; y: i32;
    state.mouse_state = transmute(MouseState) u8(SDL.GetMouseState(&x, &y))  // Cast is safe - only 5 possible values
}


StateHook :: union {
    MouseStateHook, KeyboardStateHook
}
StateHooks :: []StateHook

StateHookPair :: struct($state_type: typeid)
    where state_type == Button || state_type == KeyboardState
{
    state: state_type,
    action: StateAction
}

MouseStateHook :: StateHookPair(Button)
KeyboardStateHook :: StateHookPair(KeyboardState)  // Slightly different - slice of scancode allows for multiple keys to be mapped to the same action


StateAction :: empty_action

poll_states :: proc(controller: ^Controller, update: bool) {
    if update do get_states(&controller.states)

    /*
    for state_hook in controller.state_hooks {
        switch hook in state_hook {
            case MouseStateHook:
                if hook.state in controller.states.mouse_state do hook.action()
        }
    }
    */
}