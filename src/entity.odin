package eno

import "core:log"
import "core:testing"
import "core:fmt"
import "core:mem"

MAX_ENTITIES :: 255

Entity :: struct {
    entityId: u8,
    archetypeComponentIndex: u8
}

Archetype :: struct {
    entities: [dynamic]Entity,
    componentLabelMatch: map[string]int,
    components: [dynamic][dynamic]Component
}

LabelledComponent :: struct {
    label: string,
    component: Component
}

Component :: union {
    int, bool, f32
}

init_archetype :: proc(input_components: []LabelledComponent) -> (arch: ^Archetype, ent: ^Entity) {
    ent = new(Entity)
    ent.entityId = 0
    ent.archetypeComponentIndex = 0

    arch = new(Archetype)
    append(&arch.entities, ent^)

    components := make([dynamic][dynamic]Component, len(input_components), len(input_components))
    for &innerComponentList, i in components {
        innerComponentList = make([dynamic]Component, 1, 1) //leak
        innerComponentList[0] = input_components[i].component
        arch.componentLabelMatch[input_components[i].label] = i
    }

    arch.components = components
    return arch, ent
}

deinit_archetype :: proc(archetype: ^Archetype) {
    delete(archetype.entities)
    delete(archetype.componentLabelMatch)
    delete(archetype.components)
    free(archetype)
}


get_archetype_component_from_id :: proc(entityId: u8, label: string, archetype: ^Archetype) -> (result: ^Component) {
    //simple, enhance using queries later
    entity := &archetype.entities[entityId]
    result = &archetype.components[archetype.componentLabelMatch[label]][entity.archetypeComponentIndex]
    return result
}

//an archetype cannot exist without an entity!

@(test)
arch_test :: proc(T: ^testing.T) {
    numeric_components := [2]LabelledComponent{ LabelledComponent { "int", 5 }, LabelledComponent { "float", 12.2 }}
    archetype, entity := init_archetype(numeric_components[:])
    defer free(entity)
    defer deinit_archetype(archetype)
    fmt.printfln("archetype: %v, entity: %v", archetype, entity)
}