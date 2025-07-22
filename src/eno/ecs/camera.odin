package ecs

import cam "../camera"
import dbg "../debug"

import glm "core:math/linalg/glsl"

// Defines interaction between ecs and camera
// Each scene can have multiple cameras, and a single viewpoint - which is a reference to one camera out of the available cameras in the scene

scene_add_camera :: proc(scene: ^Scene, camera: cam.Camera) {
    append(&scene.cameras, camera)
    if len(scene.cameras) == 1 do scene.viewpoint = &scene.cameras[0]
}


scene_remove_camera :: proc(scene: ^Scene, camera_index: int) -> (ok: bool) {
    if camera_index < 0 || camera_index >= len(scene.cameras) {
        dbg.log(.ERROR, "Camera index out of range")
        return
    }
    if scene.viewpoint == &scene.cameras[camera_index] {
    // Replace viewpoint

        i: int
        for i = 0; i < len(scene.cameras); i += 1 {
            if i != camera_index {
                scene.viewpoint = &scene.cameras[i]
                break
            }
        }
        if i == len(scene.cameras) {
            dbg.log(.ERROR, "No camera to replace as scene viewpoint")
            return
        }
    }

    // todo Remove camera at index

    ok = true
    return
}

scene_perspective :: proc(scene: ^Scene) -> (perspective: glm.mat4) {
    return cam.get_perspective(scene.viewpoint)
}