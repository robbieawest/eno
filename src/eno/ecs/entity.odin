package ecs

import dbg "../debug"

import "core:mem"
import "core:slice"

// Todo: Implement
ChunkAllocator :: struct {
    
}


Entity :: struct {
    id: u32,
    archetypeColumn: u32
}


ComponentInfo :: struct {
    size: u32,  // In bytes
    label: string,
    type: typeid
}

ARCHETYPE_MAX_COMPONENTS :: 0x000FFFFF
ARCHETYPE_MAX_ENTITIES :: 0xFFFFFFFF
ARCHETYPE_INITIAL_ENTITIES_CAPACITTY :: 100
Archetype :: struct {
    entities: [dynamic]Entity,  // Allocated using default heap allocator/context allocator
    n_Components: u32,
    components_allocator: mem.Allocator,
    components: [dynamic][dynamic]byte,  // shape: ARCHETYPE_MAX_COMPONENTS * ARCHETYPE_MAX_ENTITIES
    component_infos: []ComponentInfo,
    components_label_match: map[string]u32 // Matches a label to an index from the components array
}


Scene :: struct {
    n_Archetypes: u32,
    archetypes: [dynamic]Archetype,
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
    delete(archetype.entities,loc)
    delete(archetype.component_infos, allocator, loc)
    delete(archetype.components_label_match,loc)
    
    for component_data in archetype.components do delete(component_data, loc)
    delete(archetype.components, loc)
}


// Does not free top level scene
destroy_scene :: proc(scene: ^Scene, allocator := context.allocator, loc := #caller_location) {
    delete(scene.archetype_label_match, loc)

    for &archetype in scene.archetypes do destroy_archetype(&archetype, allocator, loc)
    delete(scene.archetypes, loc)

    if scene.on_heap do free(scene, allocator, loc)
}


scene_get_archetype :: proc(scene: ^Scene, archetype_label: string) -> (archetype: ^Archetype, ok: bool) {
    archetype_index, archetype_exists := scene.archetype_label_match[archetype_label]
    if !archetype_exists {
        dbg.debug_point(dbg.LogInfo{ msg = "Attempted to retreive archetype from label which does not map to any archetype", level = .ERROR })
        return archetype, ok
    }

    return &scene.archetypes[archetype_index], true
}


archetype_get_component_data :: proc(archetype: ^Archetype, component_label: string, m: u32, n: u32) -> (component_data: []byte, ok: bool) {
    
    component_index, component_exists := archetype.components_label_match[component_label]
    if !component_exists {
        dbg.debug_point(dbg.LogInfo{ msg = "Attempted to retreive component from label which does not map to any component", level = .ERROR })
        return
    }
    
    comp_data: ^[dynamic]byte = &archetype.components[component_index]
    return comp_data[m:min(n, u32(len(comp_data)))], true
}


scene_add_archetype :: proc(scene: ^Scene, new_label: string, component_infos: ..ComponentInfo, components_allocator := context.allocator) -> (ok: bool) {
    duplicate_archetype := new_label in scene.archetype_label_match
    if duplicate_archetype {
        dbg.debug_point(dbg.LogInfo{ msg = "Attempted to create archetype with a duplicate label", level = .ERROR })
        return
    }
    
    archetype: Archetype
    archetype.component_infos = slice.clone(component_infos)
    archetype.components_allocator = components_allocator 
    archetype.n_Components = u32(len(component_infos))

    for component_info, i in component_infos {
        component_data := make([dynamic]byte, 0, ARCHETYPE_INITIAL_ENTITIES_CAPACITTY * component_info.size, components_allocator)
        append(&archetype.components, component_data)

        duplicate_component := component_info.label in archetype.components_label_match
        if duplicate_component {
            dbg.debug_point(dbg.LogInfo{ msg = "Attempted to create component with a duplicate label", level = .ERROR })
            return ok
        }

        archetype.components_label_match[component_info.label] = u32(i)
    }

    append(&scene.archetypes, archetype)
    return true
}
