package camera

import win "../window"
import "../game"
import "../ecs"

import glm "core:math/linalg/glsl"

// Defines camera instances
// Each scene can have multiple cameras, and a single viewpoint - which is a reference to one camera out of the available cameras in the scene


default_camera :: proc{ default_camera_with_position, default_camera_without_position }

@(private)
default_camera_without_position :: proc() -> (camera: ecs.Camera) {
    return ecs.Camera {
        position = { 0.0, 0.0, 0.0 },
        towards = { 0.0, 0.0, 1.0 },
        up = {0.0, 1.0, 0.0 },
        field_of_view = glm.radians_f32(90),
        aspect_ratio = win.get_aspect_ratio(game.Game.window),
        near_plane = 2.0,
        far_plane = 100.0
    }
}

@(private)
default_camera_with_position :: proc(position: glm.vec3) -> (camera: ecs.Camera) {
    return ecs.Camera {
        position = position,
        towards = { 0.0, 0.0, 1.0 },
        up = {0.0, 1.0, 0.0 },
        field_of_view = glm.radians_f32(90),
        aspect_ratio = win.get_aspect_ratio(game.Game.window),
        near_plane = 2.0,
        far_plane = 100.0
    }
}


camera_look_at :: proc{ camera_look_at_updated_position, camera_look_at_position }

camera_look_at_updated_position :: proc(
    camera: ^ecs.Camera,
    position: glm.vec3,
    towards: glm.vec3,
    up: glm.vec3
) {
    camera.position = position; camera.towards = towards; camera.up = up
    camera_look_at_position(camera)
}

camera_look_at_position :: proc(camera: ^ecs.Camera) {
    camera.look_at = glm.mat4LookAt(camera.towards, camera.position, camera.up)
}


get_perspective :: proc{ get_camera_updated_perspective, get_camera_perspective }

get_camera_updated_perspective :: proc(
    camera: ^ecs.Camera,
    field_of_view: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32
) -> glm.mat4 {
    camera.field_of_view = field_of_view; camera.aspect_ratio = aspect_ratio; camera.near_plane = near_plane; camera.far_plane = far_plane
    return get_camera_perspective(camera)
}

get_camera_perspective :: proc(camera: ^ecs.Camera) -> glm.mat4 {
    return glm.mat4Perspective(camera.field_of_view, camera.aspect_ratio, camera.near_plane, camera.far_plane)
}