package standards

import glm "core:math/linalg/glsl"

SHADER_RESOURCE_PATH :: "./resources/shaders/"
MODEL_RESOURCE_PATH :: "./resources/models/"
TEXTURE_RESOURCE_PATH :: "./resources/textures/"

ComponentTemplate :: struct {
    label: string,
    type: typeid,
    size: int
}

WORLD_COMPONENT := ComponentTemplate{ "World", WorldComponent, size_of(WorldComponent) } // Of type WorldComponent
VISIBLE_COMPONENT := ComponentTemplate{ "IsVisible", bool, size_of(bool) }

// Rename to World?
WorldComponent :: struct {
    position: glm.vec3,
    scale: glm.vec3,
    rotation: glm.quat
}

make_world_component :: proc(position: glm.vec3 = {0.0, 0.0, 0.0}, scale: glm.vec3 = {1.0, 1.0, 1.0}, rotation: glm.quat = 1) -> WorldComponent {
    return { position, scale, rotation }
}

model_from_world_component :: proc(world_comp: WorldComponent, transpose := false) -> (model: glm.mat4) {
    model = glm.mat4Translate(world_comp.position) * glm.mat4FromQuat(world_comp.rotation) * glm.mat4Scale(world_comp.scale)
    if transpose do model = glm.transpose(model)
    return
}

MODEL_MAT :: "m_Model"
NORMAL_MAT :: "m_Normal"


