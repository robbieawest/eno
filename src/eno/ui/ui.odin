package ui

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"

import im "../../../libs/dear-imgui"
import "../../../libs/dear-imgui/imgui_impl_sdl2"
import "../../../libs/dear-imgui/imgui_impl_opengl3"

import "core:slice"
import "core:strconv"
import "core:mem"
import dbg "../debug"

setup_ui :: proc(window: ^SDL.Window, sdl_gl_context: rawptr, allocator := context.allocator) -> (ok: bool) {
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

    init_ui_context(allocator=allocator)

    return true
}



setup_imgui_style :: proc() {
    style := im.GetStyle()
    style.WindowRounding = 1
    style.Colors[im.Col.WindowBg].w = 1

    im.StyleColorsDark()
}

destroy_ui_context :: proc() {
    dbg.log(.INFO, "Destroying UI context")
    im.DestroyContext()
    imgui_impl_sdl2.Shutdown()
    imgui_impl_opengl3.Shutdown()
    im.Shutdown()
}

// A UIElement MUST begin with im.Begin() and end with im.End()
UIElement :: #type proc() -> bool
UIContext :: struct {
    elements: [dynamic]UIElement,
    show_demo_window: bool,

    // Persistent buffers for input fields
    // Uses cstring bc idgaf
    buffers: map[cstring][]byte,
    allocator: mem.Allocator
}

Context: Maybe(UIContext)
init_ui_context :: proc(show_demo_win := false, allocator := context.allocator) {
    Context = UIContext{ make([dynamic]UIElement, allocator=allocator), show_demo_win, make(map[cstring][]byte, allocator=allocator), allocator }
}

show_demo_window :: proc(show: bool) -> (ok: bool) {
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

    imgui_impl_opengl3.NewFrame()
    imgui_impl_sdl2.NewFrame()
    im.NewFrame()

    if ctx.show_demo_window do im.ShowDemoWindow(nil)

    for element in ctx.elements do element() or_return

    im.Render()
    gl.Viewport(0, 0, display_w, display_y)
    imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

    backup_current_window := SDL.GL_GetCurrentWindow()
    im.UpdatePlatformWindows()

    backup_current_context := SDL.GL_GetCurrentContext()
    im.RenderPlatformWindowsDefault()
    SDL.GL_MakeCurrent(backup_current_window, backup_current_context);

    return true
}


toggle_mouse_usage :: proc() {
    io := im.GetIO()
    if .NoMouse in io.ConfigFlags {
        io.ConfigFlags -= { .NoMouse }
    }
    else do io.ConfigFlags += { .NoMouse }
}

DEFAULT_CHAR_LIMIT: uint : 10
text_input :: proc(label: cstring, #any_int char_limit: uint = DEFAULT_CHAR_LIMIT, flags: im.InputTextFlags = {}) -> (result: string, ok: bool) {
    ctx := check_context() or_return
    buf := get_buffer(ctx, label, char_limit)

    im.InputText(label, cstring(raw_data(buf)), char_limit, flags)
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
    return transmute(string)buf, true
}

int_text_input :: proc(label: cstring, #any_int char_limit: uint = DEFAULT_CHAR_LIMIT) -> (result: int, ok: bool) {
    str := text_input(label, char_limit, { .CharsDecimal }) or_return
    return strconv.atoi(str), true
}

get_buffer :: proc(ctx: ^UIContext, label: cstring, size: uint) -> (buf: []byte) {
    if label in ctx.buffers {
        return ctx.buffers[label]
    }
    else {
        buf = make([]byte, size, allocator=ctx.allocator)
        ctx.buffers[label] = buf
    }

    return
}

BufferInit :: struct { label: cstring, buf: []byte }
load_buffers :: proc(buffers: ..BufferInit) -> (ok: bool) {
    ctx := check_context() or_return

    for buffer in buffers {
        if buffer.label in ctx.buffers do continue
        ctx.buffers[buffer.label] = slice.clone(buffer.buf, ctx.allocator)
    }

    return true
}

delete_buffers :: proc(buffers: ..cstring) -> (ok: bool) {
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
check_buffer :: proc(label: cstring, buf: []byte) -> (new_buf: [^]byte, ok: bool) {
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