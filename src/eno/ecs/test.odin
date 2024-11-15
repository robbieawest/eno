package ecs

import "core:testing"

TestPositionComponent :: struct {
    x: f32,
    y: f32
}

@(test)
query_archetype_test :: proc(t: ^testing.T) {
    scene := init_scene()

    scene_add_archetype(scene, "testArchetype", ComponentInfo{ size = size_of(TestPositionComponent), label = "position", type = typeid_of(TestPositionComponent) })

    archetype: ^Archetype = scene_get_archetype(scene, "testArchetype")
    archetype_add_entity(scene, archetype, "testEntity", )
}
