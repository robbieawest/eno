package render

import standards "../standards"
import "../resource"
import dbg "../debug"

// Defines render settings, that which you would set in the ui
// Think of each of these settings as a hierarchical menu item in the ui

RenderSettings :: struct {
    environment_settings: Maybe(EnvironmentSettings)
}
GlobalRenderSettings: RenderSettings

EnvironmentSettings :: struct {
    environment_face_size: i32,
    environment_texture_uri: string,
    ibl_settings: Maybe(IBLSettings)
}

DEFAULT_ENV_MAP :: standards.TEXTURE_RESOURCE_PATH + "drackenstein_quarry_4k.hdr"
make_environment_settings :: proc(#any_int env_face_size: i32 = 2048, env_tex_uri: string = DEFAULT_ENV_MAP, ibl_settings: Maybe(IBLSettings) = nil) -> EnvironmentSettings {
    return { env_face_size, env_tex_uri, ibl_settings }
}

set_environment_settings :: proc(
    manager: ^resource.ResourceManager,
    settings: EnvironmentSettings,
    allocator := context.allocator,
    loc := #caller_location
) -> (ok: bool) {
    GlobalRenderSettings.environment_settings = settings

    // Reset environment
    destroy_image_environment(Context.image_environment)
    make_image_environment(manager, settings.environment_texture_uri, settings.environment_face_size, allocator=allocator) or_return
    if settings.ibl_settings != nil do ibl_render_setup(manager, allocator, loc) or_return
    return true
}

disable_environment_settings :: proc() {
    destroy_image_environment(Context.image_environment)
    Context.image_environment = nil
    GlobalRenderSettings.environment_settings = nil
}

IBL_ENABLED :: "enableIBL"
IBLSettings :: struct {
    prefilter_map_face_size: i32,
    irradiance_map_face_size: i32,
    brdf_lut_size: i32,
}

make_ibl_settings :: proc(#any_int pref_face_size: i32 = 1024, #any_int irr_face_size: i32 = 32, #any_int brdf_lut_size: i32 = 512) -> IBLSettings {
    return { pref_face_size, irr_face_size, brdf_lut_size }
}

disable_ibl_settings :: proc() {
    if GlobalRenderSettings.environment_settings == nil do return
    env_settings: ^EnvironmentSettings = &GlobalRenderSettings.environment_settings.?
    if env_settings.ibl_settings == nil do return

    destroy_ibl_in_image_environment(Context.image_environment)
    env_settings.ibl_settings = nil
}