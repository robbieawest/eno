package constant

import "../model"
import "../render"
import "../ecs"

import glm "core:math/linalg/glsl"



MODEL_COMPONENT := ecs.ComponentTemplate{ "Model", model.Model }  // Of type model.Model
WORLD_COMPONENT := ecs.ComponentTemplate{ "World", WorldComponent } // Of type WorldComponent
POINT_LIGHT_COMPONENT := ecs.ComponentTemplate{ "PointLight", render.PointLight }   // Of type render.PointLight
DIRECTIONAL_LIGHT_COMPONENT := ecs.ComponentTemplate{ "DirectionalLight", render.DirectionalLight } // Of type render.DirectionalLight
SPOT_LIGHT_COMPONENT := ecs.ComponentTemplate{ "SpotLight", render.SpotLight }
VISIBLE_COMPONENT := ecs.ComponentTemplate{ "IsVisible", bool }

WorldComponent :: struct {
    position: glm.vec3,
    scale: glm.vec3,
    rotation: glm.quat
}
