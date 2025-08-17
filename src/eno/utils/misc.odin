package utils

import "../standards"
import dbg "../debug"

import "core:log"
import "core:testing"

unwrap_maybe_ptr :: proc(maybe: ^Maybe($T), loc := #caller_location) -> (val: ^T, ok: bool) {
    if maybe == nil {
        dbg.log(dbg.LogLevel.ERROR, "Given maybe is invalid (nil)", loc=loc)
        return
    }
    return &maybe.?, true
}

unwrap_maybe:: proc(maybe: Maybe($T), loc := #caller_location) -> (val: T, ok: bool) {
    if maybe == nil {
        dbg.log(dbg.LogLevel.ERROR, "Given maybe is invalid (nil)", loc=loc)
        return
    }

    return maybe.?, true
}

combine_world_components :: proc(a: standards.WorldComponent, b: standards.WorldComponent) -> (comp: standards.WorldComponent) {
    comp.position = a.position + b.position
    comp.rotation = a.rotation * b.rotation
    comp.scale = a.scale * b.scale
    return
}

@(test)
combine_world_comps_test :: proc(t: ^testing.T) {
    def_rot: quaternion128
    log.infof("default rotation: %v", def_rot)
    a := standards.make_world_component(rotation=quaternion(imag=0, jmag=0, kmag=0, real=0))
    b := standards.make_world_component(rotation=quaternion(imag=0.7071, jmag=0.7071, kmag=0, real=1))
    combine_world_components(a, b)
}