package ecs

import dbg "../debug"

import "core:mem"
import "core:slice"
import "core:fmt"

// Todo: Implement
ChunkAllocator :: struct {
    
}


Entity :: struct {
    id: u32,
    archetype_column: u32
}


ComponentInfo :: struct {
    size: u32,  // In bytes
    label: string,
    type: typeid
}

ArchetypeComponentInfo :: struct {
    total_size_per_entity: u32,
    component_infos: []ComponentInfo
}

ARCHETYPE_MAX_COMPONENTS : u32 : 0x000FFFFF
ARCHETYPE_MAX_ENTITIES : u32 : 0x00FFFFFF 
ARCHETYPE_INITIAL_ENTITIES_CAPACITTY : u32 : 100
Archetype :: struct {
    n_Entities: u32,
    entities: map[string]Entity,  // Allocated using default heap allocator/context allocator
    n_Components: u32,
    components_allocator: mem.Allocator,
    components: [dynamic][dynamic]byte,  // shape: ARCHETYPE_MAX_COMPONENTS * ARCHETYPE_MAX_ENTITIES
    component_info: ArchetypeComponentInfo,
    components_label_match: map[string]u32 // Matches a label to an index from the components array
}

SCENE_MAX_ENTITIES : u32 : 0xFFFFFFFF
Scene :: struct {
    n_Entities: u32,
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
    return
}


// Does not free top level archetype
destroy_archetype :: proc(archetype: ^Archetype, allocator := context.allocator, loc := #caller_location) {
    delete(archetype.entities, loc)
    delete(archetype.component_info.component_infos, allocator, loc)
    delete(archetype.components_label_match, loc)
    
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
        return
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
    for component_info in component_infos {
        archetype.component_info.total_size_per_entity += component_info.size
    }
    archetype.component_info.component_infos = component_infos

    archetype.components_allocator = components_allocator 
    archetype.n_Components = u32(len(component_infos))
    archetype.components = make([dynamic][dynamic]byte, len(component_infos))

    for component_info, i in component_infos {
        duplicate_component := component_info.label in archetype.components_label_match
        if duplicate_component {
            dbg.debug_point(dbg.LogInfo{ msg = "Attempted to create component with a duplicate label", level = .ERROR })
            return
        }

        archetype.components[i] = make([dynamic]byte, 0, ARCHETYPE_INITIAL_ENTITIES_CAPACITTY * component_info.size, components_allocator)

        archetype.components_label_match[component_info.label] = u32(i)
    }

    append(&scene.archetypes, archetype)
    ok = true
    return
}

/*
   Adds entities of a single archetype
   This procedure considers only byte array component data input
   The component data is a map of slices mapping entity names to component data
   component data is assumed to be ordered as is in the archetype (look component_infos)
*/
scene_add_entities :: proc(scene: ^Scene, archetype_label: string, entity_component_data: map[string][]byte) -> (ok: bool) {

    archetype: ^Archetype = scene_get_archetype(scene, archetype_label) or_return
    for entity_label, component_data in entity_component_data {
        archetype_add_entity(scene, archetype, entity_label, component_data) or_return
    }

    ok = true
    return
}


@(private)
archetype_add_entity_checks :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string, component_data: []byte) -> (ok: bool) {
    duplicate_entity_label := entity_label in archetype.entities
    if duplicate_entity_label {
        dbg.debug_point(dbg.LogInfo{ msg = "Attempted to create entity with a duplicate label", level = .ERROR })
        return
    }

    if scene.n_Entities == SCENE_MAX_ENTITIES {
        dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Max entities limit for scene reached: %d", SCENE_MAX_ENTITIES), level = .ERROR })
        return
    }
    
    if archetype.n_Entities == ARCHETYPE_MAX_ENTITIES {
        dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Max entities limit for archetype reached: %d", ARCHETYPE_MAX_ENTITIES), level = .ERROR })
        return
    }

    if u32(len(component_data)) != archetype.component_info.total_size_per_entity {
        dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Component data size mismatch when adding entity", ARCHETYPE_MAX_ENTITIES), level = .ERROR })
        return
    }

    ok = true
    return
}

archetype_add_entity :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string, component_data: []byte) -> (ok: bool) {
    archetype_add_entity_checks(scene, archetype, entity_label, component_data) or_return

    entity: Entity
    entity.id = scene.n_Entities
    scene.n_Entities += 1

    entity.archetype_column = archetype.n_Entities
    archetype.n_Entities += 1

    // Add component data
    start_of_component: u32 = 0
    for component_info, i in archetype.component_info.component_infos {
        end_of_component := start_of_component + component_info.size
        append_elems(&archetype.components[i], ..component_data[start_of_component:end_of_component])
        start_of_component += component_info.size
    }

    ok = true
    return
}
