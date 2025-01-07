package old 

import "../../memory"
import "../../model"

import "core:log"
import "core:testing"
import "core:fmt"
import "core:mem"
import "core:reflect"

import "base:runtime"

// Needs a rewrite or two

// ************** Entities ****************

MAX_ENTITIES: u8 = 255
CurrentEntity: u8 = 0


Entity :: struct {
    entityId: u8,
    archetypeComponentIndex: u8
}

// ****************************************

// ************** Archetypes ****************

Archetype :: struct {
    label: string,
    entities: [dynamic]Entity,
    componentLabelMatch: map[string]int,
    components: [dynamic][dynamic]Component
}


init_archetype :: proc(label: string, input_components: []LabelledComponent) -> (arch: ^Archetype) {
    ent := new(Entity)
    defer free(ent)

    ent.entityId = CurrentEntity
    CurrentEntity += 1
    ent.archetypeComponentIndex = 0

    arch = new(Archetype)
    arch.label = label
append(&arch.entities, ent^)

    components := make([dynamic][dynamic]Component, len(input_components), len(input_components))
    for &innerComponentList, i in components {
        innerComponentList = make([dynamic]Component, 1, 1)
        innerComponentList[0] = input_components[i].component
        arch.componentLabelMatch[input_components[i].label] = i
    }

    arch.components = components
    return arch
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
    archetypeLabelMatch: map[string]int,
    archetypes: [dynamic]Archetype
}


init_scene_empty :: proc() -> ^Scene {
    return new(Scene, context.allocator)
}


init_scene_with_archetypes :: proc(archetypes: [dynamic]Archetype) -> (result: ^Scene) {
    result = new(Scene)
    for archetype, i in archetypes do result.archetypeLabelMatch[archetype.label] = i
    result.archetypes = archetypes
    return result
}


init_scene :: proc{ init_scene_empty, init_scene_with_archetypes }


destroy_scene :: proc(scene: ^Scene) {
    for &archetype in scene.archetypes do destroy_archetype(&archetype)
    free(scene)
}


add_arch_to_scene :: proc(scene: ^Scene, archetype: ^Archetype) {
    append(&scene.archetypes, archetype^)
    free(archetype)
}

// **************************************

// ************** Misc utilities ****************


//no use
initialize_component_of_component_type :: proc (eComponent: ^Component) -> any {
    type: typeid = reflect.union_variant_typeid(eComponent^)

    a := memory.alloc_dynamic(type) or_else nil
    if a == nil do log.error("Could not allocate component type, runtime allocator error")
    return a
}

// **************************************

@(test)
arch_test :: proc(T: ^testing.T) {
    numeric_components := [2]LabelledComponent{ LabelledComponent { "int", 5 }, LabelledComponent { "float", 12.2 }}
    archetype:= init_archetype("testArch", numeric_components[:])
    defer destroy_archetype(archetype)
    fmt.printfln("archetype: %v", archetype)
}


@(test)
inner_comp_test ::proc(T: ^testing.T) {

    scene: ^Scene = init_scene_empty()
    defer destroy_scene(scene)

    numeric_components := [2]LabelledComponent{ LabelledComponent { "int", 5 }, LabelledComponent { "float", 12.2 }}
    archetype := init_archetype("testArch", numeric_components[:])

    add_arch_to_scene(scene, archetype) //free's top level archetype definition, could just do add_arch_to_scene(scene, init_archetype(...))
    add_entities_of_archetype("testArch", 3, scene)

    log.infof("scene: %v", scene)
    fmt.println("break")
}
