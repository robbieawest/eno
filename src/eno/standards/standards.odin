package standards

import glm "core:math/linalg/glsl"

SHADER_RESOURCE_PATH :: "./resources/shaders/"
MODEL_RESOURCE_PATH :: "./resources/models/"

ComponentTemplate :: struct {
    label: string,
    type: typeid,
    size: int
}

WORLD_COMPONENT := ComponentTemplate{ "World", WorldComponent, size_of(WorldComponent) } // Of type WorldComponent
VISIBLE_COMPONENT := ComponentTemplate{ "IsVisible", bool, size_of(bool) }

WorldComponent :: struct {
    position: glm.vec3,
    scale: glm.vec3,
    rotation: glm.quat
}

model_from_world_component :: proc(world_comp: WorldComponent) -> (model: glm.mat4) {
    model = glm.mat4Scale(world_comp.scale)
    model *= glm.mat4Translate(world_comp.position)
    model *= glm.mat4FromQuat(world_comp.rotation)
    return
}

MODEL_MAT :: "m_Model"
NORMAL_MAT :: "m_Normal"


primitive_square_mesh_data :: proc() -> (vertices: [12]f32, indices: [6]u32) {
    return [12]f32 {
        -1, 1, 0,
        1, 1, 0,
        -1, -1, 0,
        1, -1, 0
    },
    [6]u32 {
        0, 1, 2,
        1, 2, 3
    }
}