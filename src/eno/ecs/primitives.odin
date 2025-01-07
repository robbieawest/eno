package ecs

import "../gpu"

import "core:math/linalg"

// Defines primitive components, e.g. components which are standard across entities
// Examples are 3D positions, which should be represented using the same component to be compatible with engine functionality
// There are other primitive components not defined in this file, such as DrawProperties


Position3DInfo := ComponentInfo {
    size = 12,
    label = "position",
    type = linalg.Vector3f32
}

Scale3DInfo := ComponentInfo {
    size = 12,
    label = "scale",
    type = linalg.Vector3f32
}


DrawPropertiesInfo := ComponentInfo {
    size = size_of(gpu.DrawProperties),
    label = "draw_properties",
    type = gpu.DrawProperties
}
