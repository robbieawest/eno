package render

import im "../../../libs/dear-imgui/"
import "../ui"

import dbg "../debug"

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
            return true
        }

    }

    return true
}