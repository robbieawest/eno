package ecs

import dbg "../debug"

import "core:mem"

// Todo: Implement
ChunkAllocator :: struct {
    
}


Entity :: struct {
    id: u32,
    archetypeColumn: u32
}


ComponentInfo :: struct {
    size: u32,
    label: string,
    type: typeid
}

ARCHETYPE_MAX_COMPONENTS :: 0x000FFFFF
ARCHETYPE_MAX_ENTITIES :: 0xFFFFFFFF
ARCHETYPE_INITIAL_ENTITIES_CAPACITTY :: 100
Archetype :: struct {
    entities: [dynamic]Entity,  // Allocated using default heap allocator/context allocator
    n_Components: u32,
    components_allocator: mem.Allocator
    components: [dynamic][dynamic]byte  // shape: ARCHETYPE_MAX_COMPONENTS * ARCHETYPE_MAX_ENTITIES
    component_infos: []ComponentInfo,
    component_label_match: map[string]u32 // Matches a label to an index from the components array
}


Scene :: struct {
    n_Archetypes: u32
    archetypes: [dynamic]Archetype
    archetype_label_match: map[string]u32,  // Maps string label to index in archetypes
    on_heap: bool
}


// Heap allocates scene (archetype data is not heap allocated)
// Scene should be stack allocated if possible (archetype data is allocated not on stack)
init_scene :: proc() -> (scene: ^Scene) {
    scene = new(Scene)
    scene.on_heap = true
    return scene
}


// Does not free top level archetype
destroy_archetype :: proc(archetype: ^Archetype, allocator := context.allocator, loc := #caller_location) {
    delete(archetype.entities, allocator, loc)
    delete(archetype.component_infos, allocator, loc)
    delete(archetype.component_label_match, allocator, loc)
    
    for component_data in archetype.components do delete(component_data, allocator, loc)
    delete(archetype.components, allocator, loc)
}


// Does not free top level scene
destroy_scene :: proc(scene: ^Scene, allocator := context.allocator, loc := #caller_location) {
    delete(scene.archetype_label_match, allocator, loc)

    for archetype in scene.archetypes do destroy_archetype(archetype, allocator, loc)
    delete(scene.archetypes, allocator, loc)

    if scene.on_heap do free(scene, allocator, loc)
}


scene_get_archetype :: proc(scene: ^Scene, archetype_label: string) -> (archetype: ^Archetype, ok: bool) {
    match_index := scene.archetype_label_match[archetype_label]
    if match_index == nil {
        dbg.debug_point(dbg.LogInfo{ msg = "Attempted to retreive archetype from label which does not map to any archetype", level = .ERROR })
        return archetype, ok
    }

    return scene.archetypes[match_index], true
}


archetype_get_component_data :: proc(archetype: ^Archetype, component_label: string, m: u32, n: u32) -> (component_data: []byte, ok: bool) {
    
    match_index := archetype.component_label_match[component_label]
    if match_index == nil {
        dbg.debug_point(dbg.LogInfo{ msg = "Attempted to retreive component from label which does not map to any component", level = .ERROR })
        return component_data, ok
    }
    
    comp_data: ^[dynamic]byte = &archetype.components[match_index]
    return comp_data[match_index][m:min(n, len(comp_data))]
}


scene_add_archetype :: proc(scene: ^Scene, new_label: string, component_infos: ..ComponentInfo) -> (ok: bool) {
    match_index := scene.archetype_label_match[new_label]
    if match_index != nil {
        dbg.debug_point(dbg.LogInfo{ msg = "Attempted to create archetype with a duplicate label", level = .ERROR })
        return ok
    }

    // todo
}
