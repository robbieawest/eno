package camera

import glm "core:math/linalg/glsl"
import "core:log"

Camera :: struct {
    position: [3]f32,
    towards: [3]f32,  // A direction vector - check if needs to be norm
    up: [3]f32,
    look_at: glm.mat4,
    field_of_view: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32,
    label: string,
    move_speed: f32,
    move_amp: [3]f32,  // Allows one to modulate the velocite at finer details than a simple scalar

    pitch: f32,
    yaw: f32,
    roll: f32
}


DEFAULT_POSITION : [3]f32 : { 0.0, 0.0, 0.0 }
DEFAULT_TOWARDS : [3]f32 : { 0.0, 0.0, -1.0 }
DEFAULT_UP : [3]f32 : { 0.0, 1.0, 0.0 }
DEFAULT_FOV: f32 : 45
DEFAULT_ASPECT : f32 : 1.77
DEFAULT_NEAR_PLANE : f32: 0.1
DEFAULT_FAR_PLANE : f32: 100.0
DEFAULT_MOVSPD : f32 : 1.0
DEFAULT_MOVAMP : [3]f32 : { 1.0, 1.0, 1.0 }
DEFAULT_PITCH : f32 : 0.0
DEFAULT_YAW : f32 : 0.0
DEFAULT_ROLL : f32 : 0.0


camera_look_at :: proc{ camera_look_at_updated_position, camera_look_at_position }

camera_look_at_updated_position :: proc(
camera: ^Camera,
position: [3]f32,
towards: [3]f32,
up: [3]f32
) -> (look_at: glm.mat4) {
    camera.position = position; camera.towards = towards; camera.up = up
    return camera_look_at_position(camera)
}

camera_look_at_position :: proc(camera: ^Camera) -> (look_at: glm.mat4) {
    camera.look_at = glm.mat4LookAt(camera.position, camera.position + camera.towards, camera.up)
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


move :: proc(camera: ^Camera, direction: [3]f32) {
    assert(camera != nil)
    camera.position += apply_movement_modulation(camera, direction)
}

move_unmodulated :: proc(camera: ^Camera, direction: [3]f32) {
    assert(camera != nil)
    camera.position += direction
}

/*
    Moves the camera relative to the yaw of the camera
    Used for keyboard controls for example
    May be buggy for values which are not normalized or are not WASD directions
*/
move_with_yaw :: proc(camera: ^Camera, direction: [3]f32) {
    assert(camera != nil)

     direction_without_y := [3]f32{ direction[0], 0.0, direction[2] }

    length := glm.length(direction_without_y)

    angle_from_default_towards := glm.acos(glm.dot(direction_without_y, DEFAULT_TOWARDS) / (length + 0.00001))
    if direction_without_y.x < 0 do angle_from_default_towards *= -1

    new_direction_angle := angle_from_default_towards + glm.radians(camera.yaw)
    new_direction := [3]f32{ length * glm.cos(new_direction_angle),  direction[1], length * glm.sin(new_direction_angle) }

    move(camera, new_direction)
}

MOVE_SPEED_SCALING :: 0.00025
/*
    camera unchecked
*/
@(private)
apply_movement_modulation :: proc(camera: ^Camera, direction: [3]f32) -> [3]f32 {
    vec := direction * camera.move_speed * MOVE_SPEED_SCALING
    return { camera.move_amp.x * vec.x, camera.move_amp.y * vec.y, camera.move_amp.z * vec.z }
}
