package render

import im "../../../libs/dear-imgui/"
import "../ui"
import utils "../utils"

import dbg "../debug"
import slice "core:slice"
import "core:strconv"
import "base:intrinsics"

UIRenderBuffer :: enum {
    ENV_FACE,
    ENV_TEX_URI
}

// Not declaring as constant because taking pointer of Buffers is needed for slice.enumerated_array
Buffers := [UIRenderBuffer]cstring {
    .ENV_FACE = "##env_face_size",
    .ENV_TEX_URI = "##env_tex_uri"
}

BUF_CHAR_LIM :: ui.DEFAULT_CHAR_LIMIT

delete_bufs :: proc() -> (ok: bool) {
    return ui.delete_buffers(..slice.enumerated_array(&Buffers))
}

load_bufs :: proc() -> (ok: bool) {
    settings, settings_ok := GlobalRenderSettings.unapplied_environment_settings.?
    if !settings_ok {
        dbg.log(.ERROR, "Settings must be available to load bufs")
        return
    }

    buf_infos: [len(UIRenderBuffer)]ui.BufferInit
    buffers := slice.enumerated_array(&Buffers)

    i := 0
    for buf, buf_type in Buffers {
        str_buf: string
        byte_buf := make([]byte, BUF_CHAR_LIM, Context.allocator)
        buf_type: UIRenderBuffer = buf_type  // Intellij doesn't know the type

        switch buf_type {
            case .ENV_FACE:
                str_buf = strconv.itoa(byte_buf, int(settings.environment_face_size))
            case .ENV_TEX_URI:
                byte_buf = slice.clone(transmute([]byte)(settings.environment_texture_uri), Context.allocator)
        }

        buf_infos[i] = { buf, byte_buf }
        i += 1
    }

    ui.load_buffers(..buf_infos[:])

    for info in buf_infos do delete(info.buf, Context.allocator)

    return true
}

render_settings_ui_element : ui.UIElement : proc() -> (ok: bool) {
    if Context.manager == nil {
        dbg.log(.ERROR, "Render context manager is not yet set")
        return
    }

    im.Begin("Render settings")
    defer im.End()

    if im.TreeNode("Image environment settings") {
        defer im.TreePop()

        if GlobalRenderSettings.environment_settings != nil {
            if im.Button("Disable Image Environment") {
                disable_environment_settings()
                delete_bufs()
                return true
            }
            // Show environment settings
            env_settings: ^EnvironmentSettings = &GlobalRenderSettings.unapplied_environment_settings.?

            im.Text("Environment face size:")
            new_env_face_size := ui.int_text_input("##env_face_size") or_return
            if new_env_face_size != nil do env_settings.environment_face_size = i32(new_env_face_size.?)

            im.Text("Environment texture uri")
            new_env_tex_uri := ui.text_input("##env_tex_uri") or_return
            if new_env_tex_uri != nil do env_settings.environment_texture_uri = new_env_tex_uri.?

            if im.Button("Apply image environment settings") {
                apply_environment_settings(Context.manager, Context.allocator)
            }

            if im.TreeNode("IBL Settings") {
                defer im.TreePop()
                if env_settings.ibl_settings == nil {
                    if im.Button("Enable IBL") {
                        env_settings.ibl_settings = make_ibl_settings()
                        // set_environment_settings(env_settings^)
                        apply_environment_settings(Context.manager, Context.allocator) or_return
                        return true
                    }
                }
                else {
                    if im.Button("Disable IBL") {
                        disable_ibl_settings()
                        return true
                    }
                }
            }
        }
        else do if im.Button("Enable Image Environment") {
            set_environment_settings(make_environment_settings())
            apply_environment_settings(Context.manager, Context.allocator) or_return
            load_bufs() or_return
            return true
        }

    }

    return true
}