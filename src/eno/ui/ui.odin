package ui

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"

import im "../../../libs/dear-imgui"
import "../../../libs/dear-imgui/imgui_impl_sdl2"
import "../../../libs/dear-imgui/imgui_impl_opengl3"

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

    init_ui_context(allocator)

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
UIElement :: #type proc()
UIContext :: struct {
    elements: [dynamic]UIElement
}

Context: Maybe(UIContext)
init_ui_context :: proc(allocator := context.allocator) {
    Context = UIContext{ make([dynamic]UIElement, allocator=allocator)}
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

    im.ShowDemoWindow(nil)

    if im.Begin("Window containing a quit button") {
        if im.Button("The quit button in question") {
            dbg.log(.INFO, "Quit button hit")
            return
        }
    }
    im.End()

    for element in ctx.elements do element()

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