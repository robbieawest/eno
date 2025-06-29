package old

import "../../resource"
import "../../gpu"


LabelledComponent :: struct {
    label: string,
    component: Component
}


Component :: union {
    int, bool, f32,
    CenterPosition,
    gpu.DrawProperties
}


DEFAULT_CENTER_POSITION: CenterPosition
CenterPosition :: struct {
    x: f32,
    y: f32,
    z: f32
}
