package ecs

import dbg "../debug"

import "core:testing"
import "core:log"


TestPositionComponent :: struct {
    x: f32,
    y: f32
}


@(test)
serialize_test :: proc(t: ^testing.T) {
    component := TestPositionComponent{ 0.25, 0.58 }; p_Component := &component
    comp: ECSComponentData = serialize_component(ComponentData(TestPositionComponent){ "test_label", p_Component })
    defer destroy_ecs_component_data(comp)

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
    deserialize_ret, _ := component_deserialize(TestPositionComponent, comp)
    log.infof("deserialize ret: %#v", deserialize_ret)
   
    // extract data from any type
    component_deserialized: ^TestPositionComponent = deserialize_ret.data
    defer free(component_deserialized)
    testing.expect_value(t, f32(0.25), component_deserialized.x)
    testing.expect_value(t, f32(0.58), component_deserialized.y)
}

@(test)
serialize_many_test :: proc(t: ^testing.T) {

    component := TestPositionComponent{ 0.25, 0.58 }; p_Component := &component
    component1 := TestPositionComponent{ 0.32, 59.81 }; p_Component1 := &component1
    component2 := TestPositionComponent{ -0.32, 159.81 }; p_Component2 := &component2

    serialize_ret: []ECSComponentData = components_serialize(context.allocator, TestPositionComponent,
        ComponentData(TestPositionComponent) { "component 0", p_Component },
        ComponentData(TestPositionComponent) { "component 1", p_Component1 },
        ComponentData(TestPositionComponent) { "component 2", p_Component2 },
    )
    defer delete(serialize_ret)
    //defer components_destroy(serialize_ret) deleted later, uncomment and bad free

    log.infof("serialize many ret: %#v", serialize_ret)
   
    expected := []TestPositionComponent{component, component1, component2}
    deserialize_many_ret, _ := components_deserialize(TestPositionComponent, ..serialize_ret)
    defer {
        for ret in deserialize_many_ret {
            free(ret.data)
            delete(ret.label)
        }
        delete(deserialize_many_ret)
    }

    log.infof("deserialize many ret: %#v", deserialize_many_ret)

    testing.expect_value(t, len(expected), len(deserialize_many_ret))

    for i := 0; i < len(expected); i += 1 {
        testing.expect_value(t, expected[i], deserialize_many_ret[i].data^)
    }
}


@(test)
query_archetype_test :: proc(t: ^testing.T) {
    scene := init_scene()
    defer destroy_scene(scene)

    dbg.init_debug_stack()
    defer dbg.destroy_debug_stack()

    // Todo make new
}
