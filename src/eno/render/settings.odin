package render

import standards "../standards"
import "../resource"
import dbg "../debug"

import "core:strings"

// Defines render settings, that which you would set in the ui
// Think of each of these settings as a hierarchical menu item in the ui

RenderSettings :: struct {
    environment_settings: Maybe(EnvironmentSettings),
    unapplied_environment_settings: Maybe(EnvironmentSettings),
    direct_lighting_settings: Maybe(DirectLightingSettings),
    unapplied_direct_lighting_settings: Maybe(DirectLightingSettings), // Useless right now but alas
}
GlobalRenderSettings: RenderSettings

EnvironmentSettings :: struct {
    environment_face_size: i32,
    environment_texture_uri: string,
    ibl_settings: Maybe(IBLSettings),
}

DirectLightingSettings :: struct {
    // Add things?
}

LightingSetting :: enum {
    IBL = 0,
    DIRECT_LIGHTING = 1
}
LightingSettings :: bit_set[LightingSetting; u32]
LIGHTING_SETTINGS :: "lightingSettings"

get_lighting_settings :: proc() -> (res: LightingSettings) {
    if GlobalRenderSettings.environment_settings != nil {
        env_settings := GlobalRenderSettings.environment_settings.?
        if env_settings.ibl_settings != nil do res |= { .IBL }
    }
    if GlobalRenderSettings.direct_lighting_settings != nil do res |= { .DIRECT_LIGHTING }
    return
}

DEFAULT_ENV_MAP :: standards.TEXTURE_RESOURCE_PATH + "drackenstein_quarry_4k.hdr"
make_environment_settings :: proc(#any_int env_face_size: i32 = 2048, env_tex_uri: string = DEFAULT_ENV_MAP, ibl_settings: Maybe(IBLSettings) = nil) -> EnvironmentSettings {
    return { env_face_size, env_tex_uri, ibl_settings }
}

// For use in apply procedures
compare_environment_settings :: proc(a: EnvironmentSettings, b: EnvironmentSettings) -> bool {
    return a.environment_face_size == b.environment_face_size && strings.compare(a.environment_texture_uri, b.environment_texture_uri) == 0 && a.ibl_settings == b.ibl_settings
}

set_environment_settings :: proc(settings: EnvironmentSettings) {
    GlobalRenderSettings.unapplied_environment_settings = settings
}

apply_environment_settings :: proc(manager: ^resource.ResourceManager, allocator := context.allocator, loc := #caller_location) -> (ok: bool) {
    if GlobalRenderSettings.unapplied_environment_settings == nil {
        dbg.log(.ERROR, "Unapplied environment settings cannot be nil in apply")
        return
    }

    exist_settings := GlobalRenderSettings.environment_settings
    settings := GlobalRenderSettings.unapplied_environment_settings.?

    GlobalRenderSettings.environment_settings = GlobalRenderSettings.unapplied_environment_settings

    // Set settings back, make sure strings which apply to a text buffer are copied or they will always copy the unapplied's field
    new_settings := settings
    new_settings.environment_texture_uri = strings.clone(new_settings.environment_texture_uri, allocator=allocator)
    GlobalRenderSettings.environment_settings = new_settings

    dbg.log(.INFO, "Applied settings: %#v", GlobalRenderSettings.environment_settings)
    changed := exist_settings == nil || !compare_environment_settings(exist_settings.?, settings)
    if changed {
        destroy_image_environment(Context.image_environment)
        make_image_environment(manager, settings.environment_texture_uri, settings.environment_face_size, allocator=allocator) or_return

        if settings.ibl_settings != nil do ibl_render_setup(manager, allocator, loc) or_return
    }

    return true
}

disable_environment_settings :: proc() {
    destroy_image_environment(Context.image_environment)
    Context.image_environment = nil
    GlobalRenderSettings.environment_settings = nil
}

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

    if GlobalRenderSettings.unapplied_environment_settings == nil do return
    env_settings_unapplied: ^EnvironmentSettings = &GlobalRenderSettings.unapplied_environment_settings.?
    env_settings_unapplied.ibl_settings = nil
}


enable_direct_lighting :: proc() {
    GlobalRenderSettings.direct_lighting_settings = DirectLightingSettings{}
    GlobalRenderSettings.unapplied_direct_lighting_settings = GlobalRenderSettings.direct_lighting_settings
}

disable_direct_lighting :: proc() {
    GlobalRenderSettings.direct_lighting_settings = nil
    GlobalRenderSettings.unapplied_direct_lighting_settings = nil
}