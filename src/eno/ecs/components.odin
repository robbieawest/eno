package ecs

import "../model"

// ************** Components ****************

LabelledComponent :: struct {
    label: string,
    component: Component
}

// ****************************************

Component :: union {
    int, bool, f32,
    model.Mesh, model.IndexData, CenterPosition
}


CenterPosition :: struct {
    x: f32,
    y: f32
}
