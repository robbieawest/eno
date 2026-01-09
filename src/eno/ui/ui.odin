package ui

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"
import im "../../../libs/dear-imgui"
import "../../../libs/dear-imgui/imgui_impl_sdl2"
import "../../../libs/dear-imgui/imgui_impl_opengl3"

import dbg "../debug"
import "../utils"

import "core:strings"
import "base:runtime"
import "core:slice"
import "core:strconv"
import "core:mem"

setup_ui :: proc(window: ^SDL.Window, sdl_gl_context: rawptr, allocator := context.allocator, temp_allocator := context.temp_allocator) -> (ok: bool) {
    im.CHECKVERSION()
    im.CreateContext()

    io := im.GetIO()
    io.ConfigFlags += { .NoMouse, .DockingEnable, .ViewportsEnable }

    setup_imgui_style()

    ok = imgui_impl_sdl2.InitForOpenGL(window, sdl_gl_context)
    if !ok {
        dbg.log(.ERROR, "Could not init imgui impl for sdl2-opengl")
        return
    }
    ok = imgui_impl_opengl3.Init(nil)
    if !ok {
        dbg.log(.ERROR, "Could not init imgui impl for opengl")
        return
    }

    init_ui_context(allocator=allocator, temp_allocator=temp_allocator)

    return true
}



setup_imgui_style :: proc() {
    style := im.GetStyle()
    style.WindowRounding = 1
    style.Colors[im.Col.WindowBg].w = 1

    im.StyleColorsDark()
}

destroy_ui_context :: proc() -> (ok: bool) {
    dbg.log(.INFO, "Destroying UI context")
    /*  Always shouts at me, doesn't matter nearly enough to me to validate fixing
    im.DestroyContext()
    im.Shutdown()
    imgui_impl_sdl2.Shutdown()
    imgui_impl_opengl3.Shutdown()
    */

    ctx := check_context() or_return
    delete(ctx.elements)
    for str, byte_buf in ctx.buffers {
        delete(str, ctx.allocator)
        delete(byte_buf, ctx.allocator)
    }

    return true
}

// A UIElement MUST begin with im.Begin() and end with im.End()
UIElement :: #type proc() -> bool
UIContext :: struct {
    elements: [dynamic]UIElement,
    show_demo_window: bool,

    // Persistent buffers for input fields
    buffers: map[string][]byte,
    image_scale: [2]f32,
    allocator: mem.Allocator,
    temp_allocator: mem.Allocator
}

Context: Maybe(UIContext)
init_ui_context :: proc(show_demo_win := false, image_scale := [2]f32{ 0.25, 0.25 }, allocator := context.allocator, temp_allocator := context.temp_allocator) {
    Context = UIContext{ make([dynamic]UIElement, allocator=allocator), show_demo_win, make(map[string][]byte, allocator=allocator), image_scale, allocator, temp_allocator }
}

show_imgui_demo_window :: proc(show: bool) -> (ok: bool) {
    (check_context() or_return).show_demo_window = show
    return true
}

check_context :: proc() -> (ctx: ^UIContext, ok: bool) {
    if Context == nil {
        dbg.log(.ERROR, "UI Context has not been initialized")
        return
    }
    return &Context.?, true
}

add_ui_elements :: proc(elements: ..UIElement) -> (ok: bool) {
    ctx := check_context() or_return
    append_elems(&ctx.elements, ..elements)
    return true
}

render_ui :: proc(#any_int display_w, #any_int display_y: i32) -> (running: bool) {
    ctx := check_context() or_return

    backup_current_window := SDL.GL_GetCurrentWindow()
    backup_current_context := SDL.GL_GetCurrentContext()

    imgui_impl_opengl3.NewFrame()
    imgui_impl_sdl2.NewFrame()
    im.NewFrame()

    if ctx.show_demo_window do im.ShowDemoWindow(nil)

    for element in ctx.elements do element() or_return

    im.Render()
    gl.Viewport(0, 0, display_w, display_y)
    imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

    im.UpdatePlatformWindows()
    im.RenderPlatformWindowsDefault()

    SDL.GL_MakeCurrent(backup_current_window, backup_current_context);

    free_err := free_all(allocator=ctx.temp_allocator)
    if free_err != .None {
        dbg.log(.ERROR, "Error while clearing UI temporary allocator")
        return
    }

    return true
}


toggle_mouse_usage :: proc() {
    io := im.GetIO()
    if .NoMouse in io.ConfigFlags {
        io.ConfigFlags -= { .NoMouse }
    }
    else do io.ConfigFlags += { .NoMouse }
}

// Includes null character
DEFAULT_NUMERIC_CHAR_LIMIT: uint : 10
DEFAULT_TEXT_CHAR_LIMIT: uint : 75
DEFAULT_FLOAT_CHAR_LIMIT : uint : 20

text_input :: proc(label: string, #any_int char_limit: uint = DEFAULT_TEXT_CHAR_LIMIT, flags: im.InputTextFlags = {}) -> (result: string, changed: bool, ok: bool) {
    ctx := check_context() or_return
    buf := get_buffer(ctx, label, char_limit)
    // dbg.log(.INFO, "Buf of label '%s': %v", label, buf)
    assert(buf[len(buf) - 1] == 0)
    c_label := strings.clone_to_cstring(label, ctx.temp_allocator)
    changed = im.InputText(c_label, cstring(raw_data(buf)), len(buf), flags)
    if buf == nil {
        dbg.log(.ERROR, "Buf is nil")
        return
    }
    /*
    res := check_buffer(label, buf) or_return
    ok = true
    if res == nil do return
    else do return transmute(string)buf, ok
    */
    return transmute(string)buf, changed, true
}

int_text_input :: proc(label: string, #any_int char_limit: uint = DEFAULT_NUMERIC_CHAR_LIMIT) -> (result: int, changed: bool, ok: bool) {
    str: string
    str, changed = text_input(label, char_limit, { .CharsDecimal }) or_return
    return strconv.atoi(str), changed, true
}

float_text_input :: proc(label: string, #any_int char_limit: uint = DEFAULT_FLOAT_CHAR_LIMIT) -> (result: f32, changed: bool, ok: bool) {
    str: string
    str, changed = text_input(label, char_limit, { .CharsDecimal }) or_return
    return f32(strconv.atof(str)), changed, true
}

// Provide size if expecting to create the buffer
get_buffer :: proc(ctx: ^UIContext, label: string, size: uint = 0) -> (buf: []byte) {
    if label in ctx.buffers {
        return ctx.buffers[label]
    }
    else {
        buf = make([]byte, size, allocator=ctx.allocator)
        ctx.buffers[label] = buf
    }

    return
}

BufferInit :: struct { label: string, limit: uint, val: any }
load_buffers :: proc(buffer_inits: ..BufferInit) -> (ok: bool) {
    ctx := check_context() or_return

    for buffer_init in buffer_inits {
        if len(buffer_init.label) == 0 || buffer_init.label in ctx.buffers do continue
        if buffer_init.val.data == nil {
            dbg.log(.ERROR, "Buffer init value must contain data")
            return
        }

        limit := buffer_init.limit
        byte_buf: []byte
        switch buffer_init.val.id {
            case i32:
                limit = limit == 0 ? DEFAULT_NUMERIC_CHAR_LIMIT : limit
                ptr := cast(^i32)(buffer_init.val.data)
                byte_buf = int_to_buf(ptr^, limit, ctx.allocator) or_return
            case string:
                limit = limit == 0 ? DEFAULT_TEXT_CHAR_LIMIT : limit
                ptr := transmute(^string)(buffer_init.val.data)
                byte_buf = str_to_buf(ptr^, limit, ctx.allocator) or_return
            case f32:
                limit = limit == 0 ? DEFAULT_FLOAT_CHAR_LIMIT : limit
                ptr := transmute(^f32)buffer_init.val.data
                byte_buf = float_to_buf(ptr^, limit, ctx.allocator) or_return
            case:
                dbg.log(.ERROR, "Type not yet supported %v", buffer_init.val.id)
                return
        }

        ctx.buffers[strings.clone(buffer_init.label, ctx.allocator)] = byte_buf
    }

    return true
}

delete_buffers :: proc(buffers: ..string) -> (ok: bool) {
    ctx := check_context() or_return

    for buffer in buffers {
        exist_buf, buf_exists := ctx.buffers[buffer]
        if !buf_exists {
            dbg.log(.ERROR, "Attempting to delete buffer that does not map")
            return
        }

        delete(exist_buf, ctx.allocator)
        delete_key(&ctx.buffers, buffer)
    }

    return true
}

// Copies buf if new label
// Returns new_buf if the buffer has changed, nil if not
check_buffer :: proc(label: string, buf: []byte) -> (new_buf: [^]byte, ok: bool) {
    ctx := check_context() or_return

    if label not_in ctx.buffers {
        buf := slice.clone(buf, allocator=ctx.allocator)
        new_buf = raw_data(buf)
        ctx.buffers[label] = buf
    }
    else {
        e_buf := ctx.buffers[label]
        if slice.equal(e_buf, buf) do return nil, true
        else {
            ctx.buffers[label] = buf
            new_buf = raw_data(buf)
        }
    }

    ok = true
    return
}

scale_image_dims :: proc(#any_int w, h: u32) -> (dims: im.Vec2, ok: bool) {
    ctx := check_context() or_return
    return [2]f32{ f32(w), f32(h) } * ctx.image_scale, true
}

// For opengl texture coords
get_uvs :: proc() -> (uv0: [2]f32, uv1: [2]f32, ok: bool) {
    return [2]f32{ 0, 1 }, [2]f32{ 1, 0 }, true
}