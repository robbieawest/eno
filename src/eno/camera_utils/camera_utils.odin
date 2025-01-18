package camera_utils

import win "../window"
import "../game"
import cam "../camera"

import glm "core:math/linalg/glsl"

// Utilities for cameras placed elsewhere from camera package, due to circular dependency issues

default_camera :: proc{ default_camera_with_position, default_camera_without_position }

@(private)
default_camera_without_position :: proc() -> (camera: cam.Camera) {
    return cam.Camera {
        position = { 0.0, 0.0, 0.0 },
        towards = { 0.0, 0.0, -1.0 },
        up = {0.0, 1.0, 0.0 },
        field_of_view = 45,
        aspect_ratio = win.get_aspect_ratio(game.Game.window),
        near_plane = 0.1,
        far_plane = 100.0
    }
}

@(private)
default_camera_with_position :: proc(position: glm.vec3) -> (camera: cam.Camera) {
    return cam.Camera {
        position = position,
        towards = { 0.0, 0.0, -1.0 },
        up = {0.0, 1.0, 0.0 },
        field_of_view = 45,
        aspect_ratio = win.get_aspect_ratio(game.Game.window),
        near_plane = 0.1,
        far_plane = 100.0
    }
}