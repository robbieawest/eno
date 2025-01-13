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
    comp: Component = component_serialize(TestPositionComponent, make_component_data_s(p_Component, "test_label"))
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
    deserialize_ret, deserialize_ok := component_deserialize(TestPositionComponent, comp)
    testing.expect(t, deserialize_ok, "deserialize ok check")
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

    serialize_ret: []Component = components_serialize(context.allocator, TestPositionComponent,  // Odin bug needs context.allocator
            make_component_data_s(p_Component, "component 0"),
            make_component_data_s(p_Component1, "component 1"),
            make_component_data_s(p_Component2, "component 2")
    )
    defer delete(serialize_ret)
    //defer components_destroy(serialize_ret) deleted later, uncomment and bad free

    log.infof("serialize many ret: %#v", serialize_ret)
   
    expected := []TestPositionComponent{component, component1, component2}
    deserialize_many_ret, deserialize_ok := components_deserialize(TestPositionComponent, ..serialize_ret)
    defer {
        for ret in deserialize_many_ret do free(ret.data)
        delete(deserialize_many_ret)
    }

    testing.expect(t, deserialize_ok, "deserialize many ok check")
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

    scene_add_archetype(scene, "testArchetype", context.allocator, ComponentInfo{ size = size_of(TestPositionComponent), label = "position", type = TestPositionComponent })

    position := TestPositionComponent { x = 0.25, y = 19.8 }
    archetype, _ := scene_get_archetype(scene, "testArchetype")
    archetype_add_entity(scene, archetype, "test_entity",
        make_component_data_untyped_s(&position, "position")
    )

    comp_data, ok := query_component_from_archetype(archetype, "position", TestPositionComponent, "test_entity")
    defer delete(comp_data)

    testing.expect(t, ok)

    log.infof("comp data: %#v", comp_data)
    position_comp_ret := cast(^TestPositionComponent)comp_data[0].data

    testing.expect_value(t, f32(0.25), position_comp_ret.x)
    testing.expect_value(t, f32(19.8), position_comp_ret.y)
}
