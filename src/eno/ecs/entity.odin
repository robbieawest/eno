package ecs

import dbg "../debug"
import cam "../camera"
import "../resource"
import "../standards"

import "core:fmt"
import "core:mem"
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
    name: string,
    deleted: bool,
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
    label: string,
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
    delete(archetype.label)
    for _, entity in archetype.entities do delete(entity.name)
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
    dbg.log(.ERROR, "Attempted to retreive archetype from label which does not map to any archetype")
        return
    }

    return &scene.archetypes[archetype_index], true
}

/*
    Return all archetype data but instead split by specific entity parts
    This form is very workable, and is used in querying
    Why does this return [dynamic] instead of slice? No clue
*/
@(private)
archetype_get_entity_data :: proc(archetype: ^Archetype, allocator := context.allocator) -> (result: [dynamic][dynamic][dynamic]byte, ok: bool) {
    result = make([dynamic][dynamic][dynamic]byte, len(archetype.components), allocator)
    for i in 0..<len(archetype.components) {
        comp_data := archetype.components[i]
        comp_size := int(archetype.component_info.component_infos[i].size)

        result[i] = make([dynamic][dynamic]byte, archetype.n_Entities)
        for j in 0..<int(archetype.n_Entities) {
            individual_component_start := j * comp_size

            comp_res := utils.safe_slice(comp_data, individual_component_start, individual_component_start + comp_size) or_return
            result[i][j] = utils.slice_to_dynamic(comp_res)
        }
    }

    ok = true
    return
}


scene_add_default_archetype :: proc(scene: ^Scene, label: string, allocator := context.allocator) -> (ret: ^Archetype, ok: bool) {
    dbg.log(.INFO, "Adding default archetype of name: %s",  label)
    return scene_add_archetype(scene, label,
        cast(ComponentInfo)(resource.MODEL_COMPONENT),
        cast(ComponentInfo)(standards.WORLD_COMPONENT),
        cast(ComponentInfo)(standards.VISIBLE_COMPONENT),
        allocator=allocator
    )
}

scene_add_archetype :: proc(scene: ^Scene, label: string, component_infos: ..ComponentInfo, allocator := context.allocator) -> (ret: ^Archetype, ok: bool) {
    dbg.log(.INFO, "New archetype in scene: %s",  label)

    duplicate_archetype :=  label in scene.archetype_label_match
    if duplicate_archetype {
        dbg.log(.ERROR, "Attempted to create archetype with a duplicate label")
        return
    }
    

    archetype: Archetype
    archetype.label = strings.clone(label)
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
            dbg.log(.ERROR, "Attempted to create component with a duplicate label")
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
    if strings.contains(entity_label, DELETED_ENTITY_LABEL) {
        dbg.log(.ERROR, "Archetype entity name substring '%s' is reserved")
        return
    }

    duplicate_entity_label := entity_label in archetype.entities
    if duplicate_entity_label {
        dbg.log(.ERROR, "Attempted to create entity with a duplicate label: '%s'", entity_label)
        return
    }

    if scene.n_Entities == SCENE_MAX_ENTITIES {
        dbg.log(.ERROR, "Max entities limit for scene reached: %d", SCENE_MAX_ENTITIES)
        return
    }
    
    if archetype.n_Entities == ARCHETYPE_MAX_ENTITIES {
        dbg.log(.ERROR, "Max entities limit for archetype reached: %d", ARCHETYPE_MAX_ENTITIES)
        return
    }

    ok = true
    return
}

archetype_add_entity :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string, component_data: ..ECSComponentData) -> (ok: bool) {
    dbg.log(.INFO, "Adding archetype entity: %s", entity_label)
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
            dbg.log(.ERROR, "Component in ECSComponentData could not be found")
            return
        }

        append_elems(&archetype.components[comp_index], ..data.data)
    }

    ok = true
    return
}


archetype_get_entity :: proc(archetype: ^Archetype, name: string) -> (entity: Entity, ok: bool) {
    if name not_in archetype.entities {
        dbg.log(.ERROR, "'%s' is not a valid entity", name)
        return
    }

    return archetype.entities[name], true
}

@(private)
archetype_get_entity_ptr :: proc(archetype: ^Archetype, name: string) -> (entity: ^Entity, ok: bool) {
    if name not_in archetype.entities {
        dbg.log(.ERROR, "'%s' is not a valid entity", name)
        return
    }

    return &archetype.entities[name], true
}

// Just deletes the name... For standards
destroy_entity :: proc(entity: Entity) {
    delete(entity.name)
}

/*
    Depending on postpone_true_delete this will either:
        (1) false : mark entity as deleted, preserving pointers to other entity data
        (2) true : do a swap with the end entity data, O(1), and clear the deleted data, does not preserve the end entity component

    In situation (1) the entity will be deleted via (2) later in any clean_archetype_of_deletions calls
*/
DELETED_ENTITY_LABEL :: "**DELETED ENTITY**"
archetype_remove_entities :: proc(archetype: ^Archetype, entities: ..string, contains_name := false, defer_true_delete := true, allocator := context.allocator) -> (ok: bool) {

    if defer_true_delete {
        for entity_name in entities {
            entity_keys_to_delete := make([dynamic]string, allocator=allocator)
            defer delete(entity_keys_to_delete)

            if contains_name {
                for e_entity_name, &entity in archetype.entities {
                    if strings.contains(e_entity_name, entity_name) do append(&entity_keys_to_delete, strings.clone(e_entity_name, allocator=allocator))
                }
            }
            else if entity_name in archetype.entities do append(&entity_keys_to_delete, strings.clone(entity_name, allocator=allocator))

            for key in entity_keys_to_delete {
                entity := archetype.entities[key]
                if entity.deleted do continue

                dbg.log(.INFO, "Deferring deletion of entity: '%s'", entity.name)
                entity.deleted = true
                entity.name = fmt.aprintf("**DELETED ENTITY**(%d)", entity.id)

                archetype.entities[entity.name] = entity
            }

            for key_to_delete in entity_keys_to_delete {
                destroy_entity(archetype.entities[key_to_delete])
                delete_key(&archetype.entities, key_to_delete)
                delete(key_to_delete)
            }
        }
    }
    else {
        // Todo
    }

    return true
}

clean_archetype_of_deletions :: proc(archetype: ^Archetype) -> (ok: bool) {
    // Todo
    return true
}