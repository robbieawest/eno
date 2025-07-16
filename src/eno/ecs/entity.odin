package ecs

import dbg "../debug"
import cam "../camera"
import "../resource"
import "../standards"

import "core:mem"
import "core:log"
import "core:slice"
import "core:strings"
import utils "../utils"

// Todo: look into component/entity deletion and custom allocators
// Relate it to every type defined in eno

// Todo: Implement
ChunkAllocator :: struct {
    
}


Entity :: struct {
    id: u32,
    archetype_column: u32,
    name: string
}


ComponentInfo :: struct {
    label: string,
    type: typeid,
    size: int
}


ArchetypeComponentInfo :: struct {
    total_size_per_entity: int,
    component_infos: []ComponentInfo
}

ARCHETYPE_MAX_COMPONENTS :: 0x000FFFFF
ARCHETYPE_MAX_ENTITIES :: 0x00FFFFFF
ARCHETYPE_INITIAL_ENTITIES_CAPACITTY :: 100
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
    allocated: bool,
    cameras: [dynamic]cam.Camera,
    viewpoint: ^cam.Camera,
}

// Scene reside on the stack if possible
init_scene :: proc() -> (scene: ^Scene) {
    scene = new(Scene)
    scene.allocated = true
    scene.archetype_label_match = make(map[string]u32)
    scene.archetypes = make([dynamic]Archetype)
    scene.cameras = make([dynamic]cam.Camera)
    return
}


//

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
    delete(scene.cameras)

    for &archetype in scene.archetypes do destroy_archetype(&archetype, allocator, loc)
    delete(scene.archetypes, loc)

    if scene.allocated do free(scene, allocator, loc)
}


scene_get_archetype :: proc(scene: ^Scene, archetype_label: string) -> (archetype: ^Archetype, ok: bool) {
    archetype_index, archetype_exists := scene.archetype_label_match[archetype_label]
    if !archetype_exists {
    dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to retreive archetype from label which does not map to any archetype")
        return
    }

    return &scene.archetypes[archetype_index], true
}

// Unchecked component_label, should really not use unless it is already verified
archetype_get_component_data :: proc(archetype: ^Archetype, component_label: string, m: u32, n: u32) -> (component_data: []byte) {
    
    component_index := archetype.components_label_match[component_label]

    comp_data: ^[dynamic]byte = &archetype.components[component_index]
    return comp_data[m:min(n, u32(len(comp_data)))]
}

/*
    Return all archetype data but instead split by specific entity parts
    This form is very workable, and is used in querying
    Why does this return [dynamic] instead of slice? No clue
*/
@(private)
archetype_get_entity_data :: proc(archetype: ^Archetype) -> (result: [dynamic][dynamic][dynamic]byte) {
    result = make([dynamic][dynamic][dynamic]byte, len(archetype.components))
    for i in 0..<len(archetype.components) {
        comp_data := archetype.components[i]
        comp_size := int(archetype.component_info.component_infos[i].size)

        result[i] = make([dynamic][dynamic]byte, archetype.n_Entities)
        for j in 0..<int(archetype.n_Entities) {
            individual_component_start := j * comp_size
            result[i][j] = utils.slice_to_dynamic(comp_data[individual_component_start:individual_component_start + comp_size])
        }
    }
    return
}


scene_add_default_archetype :: proc(scene: ^Scene, label: string, allocator := context.allocator) -> (ret: ^Archetype, ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Adding default archetype of name: %s",  label)
    return scene_add_archetype(scene, label,
        cast(ComponentInfo)(resource.MODEL_COMPONENT),
        cast(ComponentInfo)(standards.WORLD_COMPONENT),
        cast(ComponentInfo)(standards.VISIBLE_COMPONENT),
        allocator=allocator
    )
}

scene_add_archetype :: proc(scene: ^Scene, label: string, component_infos: ..ComponentInfo, allocator := context.allocator) -> (ret: ^Archetype, ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "New archetype in scene: %s",  label)

    duplicate_archetype :=  label in scene.archetype_label_match
    if duplicate_archetype {
        dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to create archetype with a duplicate label")
        return
    }
    

    archetype: Archetype
    for component_info in component_infos {
        archetype.component_info.total_size_per_entity += component_info.size
    }
    archetype.component_info.component_infos = slice.clone(component_infos)

    archetype.components_allocator = allocator
    archetype.n_Components = u32(len(component_infos))
    archetype.components = make([dynamic][dynamic]byte, len(component_infos))
    archetype.entities = make(map[string]Entity)
    archetype.components_label_match = make(map[string]u32)

    for component_info, i in component_infos {
        duplicate_component := component_info.label in archetype.components_label_match
        if duplicate_component {
            dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to create component with a duplicate label")
            return
        }

        archetype.components[i] = make([dynamic]byte, 0, ARCHETYPE_INITIAL_ENTITIES_CAPACITTY * component_info.size, allocator)

        archetype.components_label_match[component_info.label] = u32(i)
    }

    scene.archetype_label_match[ label] = scene.n_Archetypes
    append(&scene.archetypes, archetype)
    scene.n_Archetypes += 1
    ok = true
    ret = &scene.archetypes[len(scene.archetypes) - 1]
    return
}



@(private)
archetype_add_entity_checks :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string) -> (ok: bool) {
    duplicate_entity_label := entity_label in archetype.entities
    if duplicate_entity_label {
        dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to create entity with a duplicate label")
        return
    }

    if scene.n_Entities == SCENE_MAX_ENTITIES {
        dbg.debug_point(dbg.LogLevel.ERROR, "Max entities limit for scene reached: %d", SCENE_MAX_ENTITIES)
        return
    }
    
    if archetype.n_Entities == ARCHETYPE_MAX_ENTITIES {
        dbg.debug_point(dbg.LogLevel.ERROR, "Max entities limit for archetype reached: %d", ARCHETYPE_MAX_ENTITIES)
        return
    }

    ok = true
    return
}


// Add a way with matched form? CBA
archetype_add_entity :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string, component_data: ..ECSComponentData) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Adding archetype entity: %s", entity_label)
    entity_label := strings.clone(entity_label)
    archetype_add_entity_checks(scene, archetype, entity_label) or_return

    entity: Entity
    entity.id = scene.n_Entities
    entity.name = entity_label
    scene.n_Entities += 1

    entity.archetype_column = archetype.n_Entities
    archetype.n_Entities += 1
    archetype.entities[entity_label] = entity

    for data in component_data {
        comp_index, component_exists := archetype.components_label_match[data.label]
        if !component_exists {
            dbg.debug_point(dbg.LogLevel.ERROR, "Component could not be found")
            return
        }

        append_elems(&archetype.components[comp_index], ..data.data)
    }

    ok = true
    return
}