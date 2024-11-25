package ecs

import "core:testing"
import "core:log"
import "core:fmt"

TestPositionComponent :: struct {
    x: f32,
    y: f32
}


@(test)
serialize_test :: proc(t: ^testing.T) {
    scene := init_scene()
    defer destroy_scene(scene)
    
    component := TestPositionComponent{ 0.25, 0.58 }
    comp: Component = component_serialize(TestPositionComponent, &component, "test comp", scene)
    defer component_destroy(&comp)

    log.infof("component: %#v", comp)

    f1_rep: u32 = 0
    f1_rep |= u32(comp.data[0])
    f1_rep |= u32(comp.data[1]) << 8
    f1_rep |= u32(comp.data[2]) << 16
    f1_rep |= u32(comp.data[3]) << 24
    
    out_f1 := transmute(f32)f1_rep
    testing.expect_value(t, out_f1, 0.25)

    f2_rep: u32 = 0
    f2_rep |= u32(comp.data[4])
    f2_rep |= u32(comp.data[5]) << 8
    f2_rep |= u32(comp.data[6]) << 16
    f2_rep |= u32(comp.data[7]) << 24

    out_f2 := transmute(f32)f2_rep
    testing.expect_value(t, out_f2, 0.58)
    log.infof("out f1: %f, f2: %f", out_f1, out_f2)
}



/*
@(test)
query_archetype_test :: proc(t: ^testing.T) {
    scene := init_scene()

    scene_add_archetype(scene, "testArchetype", ComponentInfo{ size = size_of(TestPositionComponent), label = "position", type = typeid_of(TestPositionComponent) })

    archetype: ^Archetype = scene_get_archetype(scene, "testArchetype")
    archetype_add_entity(scene, archetype, "")
}
*/
