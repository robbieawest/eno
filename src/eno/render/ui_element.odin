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

    if GlobalRenderSettings.environment_settings != nil {
        if im.Button("Disable Image Environment") {
            disable_environment_settings()
            return true
        }
        // Show environment settings
        env_settings := GlobalRenderSettings.environment_settings.?
        if env_settings.ibl_settings == nil {
            if im.Button("Enable IBL") {
                ibl_settings := make_ibl_settings()
                env_settings.ibl_settings = ibl_settings
                set_environment_settings(Context.manager, env_settings, Context.allocator) or_return
            }
        }
        else {
            if im.Button("Disable IBL") {
                disable_ibl_settings()
                return true
            }
        }
    }
    else do if im.Button("Enable Image Environment") {
        set_environment_settings(Context.manager, make_environment_settings(), Context.allocator) or_return
    }

    return true
}