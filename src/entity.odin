package eno

import "core:log"
import "core:testing"
import "core:fmt"
import "core:mem"

// ************** Entities ****************

MAX_ENTITIES :: 255

Entity :: struct {
    entityId: u8,
    archetypeComponentIndex: u8
}

// ****************************************

// ************** Components ****************

LabelledComponent :: struct {
    label: string,
    component: Component
}

// ****************************************

Component :: union {
    int, bool, f32
}

// ************** Archetypes ****************

Archetype :: struct {
    entities: [dynamic]Entity,
    componentLabelMatch: map[string]int,
    components: [dynamic][dynamic]Component
}

init_archetype :: proc(input_components: []LabelledComponent) -> (arch: ^Archetype, ent: ^Entity) {
    ent = new(Entity)
    ent.entityId = 0
    ent.archetypeComponentIndex = 0

    arch = new(Archetype)
    append(&arch.entities, ent^)

    components := make([dynamic][dynamic]Component, len(input_components), len(input_components))
    for &innerComponentList, i in components {
        innerComponentList = make([dynamic]Component, 1, 1)
        innerComponentList[0] = input_components[i].component
        arch.componentLabelMatch[input_components[i].label] = i
    }

    arch.components = components
    return arch, ent
}

destroy_archetype :: proc(archetype: ^Archetype) {
    delete(archetype.entities)
    delete(archetype.componentLabelMatch)
    for innerComponentList in archetype.components do delete(innerComponentList)
    delete(archetype.components)
    free(archetype)
}

// ****************************************

// ************** Scenes ****************

Scene :: struct {
    archetypes: [dynamic]Archetype
}

init_scene_empty :: proc() -> ^Scene {
    return new(Scene, context.allocator)
}

init_scene_with_archetypes :: proc(archetypes: [dynamic]Archetype) -> (result: ^Scene) {
    result = new(Scene)
    result.archetypes = archetypes
}

init_scene :: proc{ init_scene_empty, init_scene_with_archetypes }

destroy_scene :: proc(scene: ^Scene) {
    for archetype in scene.archetypes do destroy_archetype(archetype)
    delete(scene)
}


// **************************************



@(test)
arch_test :: proc(T: ^testing.T) {
    numeric_components := [2]LabelledComponent{ LabelledComponent { "int", 5 }, LabelledComponent { "float", 12.2 }}
    archetype, entity := init_archetype(numeric_components[:])
    defer free(entity)
    defer destroy_archetype(archetype)
    fmt.printfln("archetype: %v, entity: %v", archetype, entity)
}