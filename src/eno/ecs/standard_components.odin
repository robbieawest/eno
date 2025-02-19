package ecs

import glm "core:math/linalg/glsl"


MODEL_COMPONENT :: "model"  // Of type model.Model
WORLD_COMPONENT :: "world"  // Of type WorldComponent
POINT_LIGHT_COMPONENT :: "point_light"  // Of type render.PointLight
DIRECTIONAL_LIGHT_COMPONENT :: "directional_light" // Of type render.DirectionalLight
SPOT_LIGHT_COMPONNET :: "spot_light"

WorldComponent :: struct {
    position: glm.vec3,
    scale: glm.vec3,
    rotation: glm.quat
}