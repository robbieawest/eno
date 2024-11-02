package ecs

import "../model"
import "../gpu"


LabelledComponent :: struct {
    label: string,
    component: Component
}


Component :: union {
    int, bool, f32,
    CenterPosition,
    DrawProperties
}

DEFAULT_DRAW_PROPERTIES: DrawProperties
DrawProperties :: struct {
    mesh: model.Mesh,
    indices: model.IndexData,
    gpu_component: gpu.GPUComponent,
    expressed: bool
}

DEFAULT_CENTER_POSITION: CenterPosition
CenterPosition :: struct {
    x: f32,
    y: f32
}
