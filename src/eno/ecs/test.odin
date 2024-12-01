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
    component := TestPositionComponent{ 0.25, 0.58 }
    comp: Component = component_serialize(TestPositionComponent, &component, "test comp")
    defer component_destroy(comp)

    log.infof("component: %#v", comp)

    // manual deserialization
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

    // test deserialization
    deserialize_ret: any = component_deserialize(&comp)
    log.infof("deserialize ret: %#v", deserialize_ret)
   
    // extract data from any type
    component_deserialized: ^TestPositionComponent = cast(^TestPositionComponent)deserialize_ret.data
    defer free(component_deserialized)
    testing.expect_value(t, f32(0.25), component_deserialized.x)
    testing.expect_value(t, f32(0.58), component_deserialized.y)
}


@(test)
serialize_many_test :: proc(t: ^testing.T) {

    component := TestPositionComponent{ 0.25, 0.58 }
    component1 := TestPositionComponent{ 0.32, 59.81 }
    component2 := TestPositionComponent{ -0.32, 159.81 }

    serialize_ret: []Component = components_serialize(TestPositionComponent, []LabelledData(TestPositionComponent){ 
            { &component, "component 0" },
            { &component1, "component 1" },
            { &component2, "component 2" }
        }
    )
    defer components_destroy(serialize_ret)

    log.infof("serialize many ret: %#v", serialize_ret)
    
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
