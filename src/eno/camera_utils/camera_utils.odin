package camera_utils

import win "../window"
import "../game"
import cam "../camera"

import glm "core:math/linalg/glsl"
import "core:fmt"

// Utilities for cameras placed elsewhere from camera package, due to circular dependency issues


init_camera :: proc(
    label := "",
    position := cam.DEFAULT_POSITION,
    towards := cam.DEFAULT_TOWARDS,
    up := cam.DEFAULT_UP,
    field_of_view := cam.DEFAULT_FOV,
    aspect_ratio := cam.DEFAULT_ASPECT,
    near_plane := cam.DEFAULT_NEAR_PLANE,
    far_plane := cam.DEFAULT_FAR_PLANE,
    move_speed := cam.DEFAULT_MOVSPD,
    move_amp := cam.DEFAULT_MOVAMP
) -> cam.Camera {
    return cam.Camera {
        label = len(label) != 0 ? label : get_default_label(),
        position = position,
        towards = towards,
        up = up,
        field_of_view = field_of_view,
        aspect_ratio = aspect_ratio == cam.DEFAULT_ASPECT ? win.get_aspect_ratio(game.Game.window) : aspect_ratio,
        near_plane = near_plane,
        far_plane = far_plane,
        move_speed = move_speed,
        move_amp = move_amp
    }
}

get_default_label :: proc() -> string {
    num_cameras := len(game.Game.scene.cameras)
    return fmt.aprintf("Camera%i", num_cameras)
}




init_camera_old :: proc{ default_camera_with_position, default_camera_without_position }

@(private)
default_camera_without_position :: proc(label: string) -> (camera: cam.Camera) {
    return cam.Camera {
        position = { 0.0, 0.0, 0.0 },
        towards = { 0.0, 0.0, -1.0 },
        up = {0.0, 1.0, 0.0 },
        field_of_view = 45,
        aspect_ratio = win.get_aspect_ratio(game.Game.window),
        near_plane = 0.1,
        far_plane = 100.0,
        label = label
    }
}

@(private)
default_camera_with_position :: proc(label: string, position: glm.vec3) -> (camera: cam.Camera) {
    return cam.Camera {
        position = position,
        towards = { 0.0, 0.0, -1.0 },
        up = {0.0, 1.0, 0.0 },
        field_of_view = 45,
        aspect_ratio = win.get_aspect_ratio(game.Game.window),
        near_plane = 0.1,
        far_plane = 100.0,
        label = label
    }
}