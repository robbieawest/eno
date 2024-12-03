package ecs

import "../gpu"

import "core:testing"
import "core:log"
import "core:fmt"


TestPositionComponent :: struct {
    x: f32,
    y: f32
}


@(test)
serialize_test :: proc(t: ^testing.T) {
    component := TestPositionComponent{ 0.25, 0.58 }; p_Component := &component
    comp: Component = component_serialize(make_component_data(p_Component, "test_label"))
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
    deserialize_ret, deserialize_ok := component_deserialize(comp)
    testing.expect(t, deserialize_ok, "deserialize ok check")
    log.infof("deserialize ret: %#v", deserialize_ret)
   
    // extract data from any type
    component_deserialized: ^TestPositionComponent = cast(^TestPositionComponent)deserialize_ret.data
    defer free(component_deserialized)
    testing.expect_value(t, f32(0.25), component_deserialized.x)
    testing.expect_value(t, f32(0.58), component_deserialized.y)
}

@(test)
serialize_many_test :: proc(t: ^testing.T) {

    component := TestPositionComponent{ 0.25, 0.58 }; p_Component := &component
    component1 := TestPositionComponent{ 0.32, 59.81 }; p_Component1 := &component1
    component2 := TestPositionComponent{ -0.32, 159.81 }; p_Component2 := &component

    serialize_ret: []Component = components_serialize( 
            make_component_data(p_Component, "component 0"),
            make_component_data(p_Component1, "component 1"),
            make_component_data(p_Component2, "component 2")
    )
    defer components_destroy(serialize_ret)

    log.infof("serialize many ret: %#v", serialize_ret)
   
    expected := []TestPositionComponent{component, component1, component2}
    deserialize_many_ret, deserialize_ok := components_deserialize(..serialize_ret)
    defer {
        for ret in deserialize_many_ret do free(ret.data)
        delete(deserialize_many_ret)
    }

    testing.expect(t, deserialize_ok, "deserialize many ok check")
    log.infof("deserialize many ret: %#v", deserialize_many_ret)

    testing.expect_value(t, len(expected), len(deserialize_many_ret))

    for i := 0; i < len(expected); i += 1 {
        testing.expect_value(t, expected[i], (cast(^TestPositionComponent)deserialize_many_ret[i].data)^)
    }
}

/*
@(test)
act_on_archetype_test :: proc(t: ^testing.T) {

    scene := init_scene()
    scene_add_archetype(scene, "test_archetype", Position3DInfo, DrawPropertiesInfo)

    draw_properties: gpu.DrawProperties
    position: Position3D
    new_entity_match := map[string]Component { "new_entity"}
    //scene_add_entities(scene, "test_archetype", )
}
*/



/*
@(test)
query_archetype_test :: proc(t: ^testing.T) {
    scene := init_scene()

    scene_add_archetype(scene, "testArchetype", ComponentInfo{ size = size_of(TestPositionComponent), label = "position", type = typeid_of(TestPositionComponent) })

    archetype: ^Archetype = scene_get_archetype(scene, "testArchetype")
    archetype_add_entity(scene, archetype, "")
}
*/
