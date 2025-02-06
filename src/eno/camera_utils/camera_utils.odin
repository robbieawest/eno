package camera_utils

import win "../window"
import "../game"
import cam "../camera"

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
    move_amp := cam.DEFAULT_MOVAMP,
    pitch := cam.DEFAULT_PITCH,
    yaw := cam.DEFAULT_YAW,
    roll := cam.DEFAULT_ROLL,
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
        move_amp = move_amp,
        pitch = pitch,
        yaw = yaw,
        roll = roll
    }
}

get_default_label :: proc() -> string {
    num_cameras := len(game.Game.scene.cameras)
    return fmt.aprintf("Camera%i", num_cameras)
}

update_view :: proc(program: ^gpu.ShaderProgram, label := "m_View") {
    gpu.set_matrix_uniform(program, label, 1, false, cam.camera_look_at(game.Game.scene.viewpoint))
}