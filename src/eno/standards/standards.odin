package standards

import glm "core:math/linalg/glsl"

ComponentTemplate :: struct {
    label: string,
    type: typeid
}

WORLD_COMPONENT := ComponentTemplate{ "World", WorldComponent } // Of type WorldComponent
VISIBLE_COMPONENT := ComponentTemplate{ "IsVisible", bool }

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