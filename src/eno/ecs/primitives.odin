package ecs

import "../gpu"

// Defines primitive components, e.g. components which are standard across entities
// Examples are 3D positions, which should be represented using the same component to be compatible with engine functionality
// There are other primitive components not defined in this file, such as DrawProperties

Position3D :: struct {
    x: f32,
    y: f32,
    z: f32
}

Position3DInfo := ComponentInfo {
    size = 12,
    label = "position",
    type = Position3D
}


DrawPropertiesInfo := ComponentInfo {
    size = size_of(gpu.DrawProperties),
    label = "draw_properties",
    type = gpu.DrawProperties
}
