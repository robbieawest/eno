package camera

import glm "core:math/linalg/glsl"

Camera :: struct {
    position: glm.vec3,
    towards: glm.vec3,
    up: glm.vec3,
    look_at: glm.mat4,
    field_of_view: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32,
    label: string,
    move_speed: f32,
    move_amp: glm.vec3,  // Allows one to modulate the velocite at finer details than a simple scalar
}


DEFAULT_POSITION : glm.vec3 : { 0.0, 0.0, 0.0 }
DEFAULT_TOWARDS : glm.vec3 : { 0.0, 0.0, -1.0 }
DEFAULT_UP : glm.vec3 : { 0.0, 1.0, 0.0 }
DEFAULT_FOV: f32 : 45
DEFAULT_ASPECT : f32 : 1.77
DEFAULT_NEAR_PLANE : f32: 0.1
DEFAULT_FAR_PLANE : f32: 100.0
DEFAULT_MOVSPD : f32 : 1.0
DEFAULT_MOVAMP: glm.vec3 : { 1.0, 1.0, 1.0 }


// todo: Update this
camera_look_at :: proc{ camera_look_at_updated_position, camera_look_at_position }

camera_look_at_updated_position :: proc(
camera: ^Camera,
position: glm.vec3,
towards: glm.vec3,
up: glm.vec3
) -> (look_at: glm.mat4) {
    camera.position = position; camera.towards = towards; camera.up = up
    return camera_look_at_position(camera)
}

camera_look_at_position :: proc(camera: ^Camera) -> (look_at: glm.mat4) {
    camera.look_at = glm.mat4LookAt(camera.towards, camera.position, camera.up)
    return camera.look_at
}


get_perspective :: proc{ get_camera_updated_perspective, get_camera_perspective }

@(private)
get_camera_updated_perspective :: proc(
camera: ^Camera,
field_of_view: f32,
aspect_ratio: f32,
near_plane: f32,
far_plane: f32
) -> glm.mat4 {
    camera.field_of_view = field_of_view; camera.aspect_ratio = aspect_ratio; camera.near_plane = near_plane; camera.far_plane = far_plane
    return get_camera_perspective(camera)
}

@(private)
get_camera_perspective :: proc(camera: ^Camera) -> glm.mat4 {
    return glm.mat4Perspective(camera.field_of_view, camera.aspect_ratio, camera.near_plane, camera.far_plane)
}