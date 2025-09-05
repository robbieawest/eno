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
    ENV_FACE_SIZE,
    ENV_TEX_URI,
    IRR_FACE_SIZE,
    PREFILTER_FACE_SIZE,
    BRDF_LUT_SIZE
}

// Not declaring as constant because taking pointer of Buffers is needed for slice.enumerated_array
Buffers := [UIRenderBuffer]cstring {
    .ENV_FACE_SIZE = "##env_face_size",
    .ENV_TEX_URI = "##env_tex_uri",
    .IRR_FACE_SIZE = "##irr_face_size",
    .PREFILTER_FACE_SIZE = "##pref_face_size",
    .BRDF_LUT_SIZE = "##brdf_lut_size"
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

    ibl_settings, ibl_enabled := settings.ibl_settings.?

    buf_infos: [len(UIRenderBuffer)]ui.BufferInit
    buffers := slice.enumerated_array(&Buffers)

    i := 0
    for buf, buf_type in Buffers {
        byte_buf: Maybe([]byte)
        buf_type: UIRenderBuffer = buf_type  // Intellij doesn't know the type

        switch buf_type {
            case .ENV_FACE_SIZE: byte_buf = ui.int_to_buf(settings.environment_face_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
            case .ENV_TEX_URI: byte_buf = ui.str_to_buf(settings.environment_texture_uri, BUF_TEXT_CHAR_LIM, Context.allocator) or_return
            case .IRR_FACE_SIZE: if ibl_enabled do byte_buf = ui.int_to_buf(ibl_settings.irradiance_map_face_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
            case .PREFILTER_FACE_SIZE: if ibl_enabled do byte_buf = ui.int_to_buf(ibl_settings.prefilter_map_face_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
            case .BRDF_LUT_SIZE: if ibl_enabled do byte_buf = ui.int_to_buf(ibl_settings.brdf_lut_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
        }

        if byte_buf != nil do buf_infos[i] = { buf, byte_buf.? }
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
            env_settings.environment_face_size = i32(ui.int_text_input(Buffers[.ENV_FACE_SIZE]) or_return)

            im.Text("Environment texture uri")
            env_settings.environment_texture_uri = ui.text_input(Buffers[.ENV_TEX_URI]) or_return

            if im.TreeNode("IBL Settings") {
                defer im.TreePop()
                if env_settings.ibl_settings == nil {
                    if im.Button("Enable IBL") {
                        env_settings.ibl_settings = make_ibl_settings()
                        // set_environment_settings(env_settings^)
                        apply_environment_settings(Context.manager, Context.allocator) or_return
                        load_bufs() or_return
                        return true
                    }
                }
                else {
                    ibl_settings: ^IBLSettings = &env_settings.ibl_settings.?
                    im.Text("Irradiance map face size:")
                    ibl_settings.irradiance_map_face_size = i32(ui.int_text_input(Buffers[.IRR_FACE_SIZE]) or_return)

                    im.Text("Prefilter map face size:")
                    ibl_settings.prefilter_map_face_size = i32(ui.int_text_input(Buffers[.PREFILTER_FACE_SIZE]) or_return)

                    im.Text("BRDF LUT size:")
                    ibl_settings.brdf_lut_size = i32(ui.int_text_input(Buffers[.BRDF_LUT_SIZE]) or_return)

                    if im.Button("Disable IBL") {
                        disable_ibl_settings()
                        ui.delete_buffers(Buffers[.IRR_FACE_SIZE], Buffers[.PREFILTER_FACE_SIZE], Buffers[.BRDF_LUT_SIZE])
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

    if im.TreeNode("Direct lighting settings") {
        defer im.TreePop()
        if GlobalRenderSettings.direct_lighting_settings != nil {
            if im.Button("Disable direct lighting") {
                disable_direct_lighting()
            }
        }
        else {
            if im.Button("Enable direct lighting") {
                enable_direct_lighting()
            }
        }
    }

    return true
}