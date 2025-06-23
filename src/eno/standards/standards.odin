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
