package render

import im "../../../libs/dear-imgui/"
import "../ui"
import utils "../utils"

import "core:strings"
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

delete_bufs :: proc() -> (ok: bool) {
    return ui.delete_buffers(..slice.enumerated_array(&Buffers))
}

BUF_TEXT_CHAR_LIM :: ui.DEFAULT_TEXT_CHAR_LIMIT
BUF_NUMERIC_CHAR_LIM :: ui.DEFAULT_NUMERIC_CHAR_LIMIT
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
        byte_buf: []byte
        buf_type: UIRenderBuffer = buf_type  // Intellij doesn't know the type

        switch buf_type {
            case .ENV_FACE:
                if settings.environment_face_size % 10 >= i32(BUF_NUMERIC_CHAR_LIM) {
                    dbg.log(.ERROR, "Environment face size needs to many characters for ui buffer")
                    return
                }
                byte_buf = make([]byte, BUF_NUMERIC_CHAR_LIM, Context.allocator)
                strconv.itoa(byte_buf, int(settings.environment_face_size))
            case .ENV_TEX_URI:
                if uint(len(settings.environment_texture_uri)) >= BUF_TEXT_CHAR_LIM {
                    dbg.log(.ERROR, "Environment texture uri is greater than the ui buffer char limit")
                    return
                }

                byte_buf = make([]byte, BUF_TEXT_CHAR_LIM, Context.allocator)
                copy(byte_buf, transmute([]byte)(settings.environment_texture_uri))
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
            env_settings.environment_face_size = i32(ui.int_text_input("##env_face_size") or_return)

            im.Text("Environment texture uri")
            env_settings.environment_texture_uri = ui.text_input("##env_tex_uri") or_return

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

            if im.Button("Apply image environment settings") {
                apply_environment_settings(Context.manager, Context.allocator)
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