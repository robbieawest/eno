package ecs

import dbg "../debug"
import "../utils"

import "core:mem"
import "core:testing"
import "core:log"

SceneQuery :: union {
    ArchetypeQuery,  // To use the same query on all archetypes
    map[string]ArchetypeQuery  // To split by archetype
}

ArchetypeQuery :: struct {
    entities: []string,  // Ignore for now
    components: []ComponentQuery
}

ComponentQuery :: struct {
    label: string,
    include: bool,
    data: rawptr  // Give as nil to query by existence of label
}


SceneQueryResult :: map[string]ArchetypeQueryResult  // Maps scene name
ArchetypeQueryResult :: struct {
    entity_map: map[string]Entity,  // Entity struct contains the column to start into the component data
    component_map: map[string]u32,  // Maps to rows into data
    data: [dynamic][dynamic][dynamic]byte
}


delete_archetype_query_result :: proc(result: ArchetypeQueryResult) {
    for key, _ in result.entity_map do delete(key)
    delete(result.entity_map)

    for key, _ in result.component_map do delete(key)
    delete(result.component_map)

    for arr2 in result.data do delete(arr2)
    delete(result.data)
}


query_scene :: proc(scene: ^Scene, query: SceneQuery) -> (result: SceneQueryResult, ok: bool) {
    result = make(SceneQueryResult)
    switch v in query {
        case ArchetypeQuery:
            for label, ind in scene.archetype_label_match {
                result[label] = query_archetype(&scene.archetypes[ind], v)
            }
        case map[string]ArchetypeQuery:
            for archetype_label, archetype_query in v {
                archetype, archetype_exists := scene_get_archetype(scene, archetype_label)
                if !archetype_exists {
                    dbg.debug_point(dbg.LogLevel.ERROR, "Archetype label %s does not map to an existing archetype", archetype_label)
                    return
                }
                query_archetype(archetype, archetype_query)
            }
    }

    ok = true
    return
}

query_archetype :: proc(archetype: ^Archetype, query: ArchetypeQuery) -> (result: ArchetypeQueryResult) {

    result.data = archetype_get_entity_data(archetype)
    result.component_map = utils.copy_map(archetype.components_label_match)
    result.entity_map = utils.copy_map(archetype.entities)

    entity_index_to_label_map := make(map[u32]string, len(result.entity_map))
    for label, entity in result.entity_map do entity_index_to_label_map[entity.archetype_column] = label

    if len(query.components) == 0 && len(query.entities) == 0 do return result

    // Filter result
    entities_to_be_filtered := make([dynamic]Entity)

    component_remove_map := make(map[string]bool, archetype.n_Components)
    for comp_label, _ in archetype.components_label_match do component_remove_map[comp_label] = true

    for component_query in query.components {
        comp_ind, comp_exists := archetype.components_label_match[component_query.label]
        if !comp_exists do return {} // Skip archetype

        component_data: [dynamic][dynamic]byte = result.data[comp_ind]
        if component_query.data != nil {
            for component, i in component_data {
                if mem.compare_ptrs(raw_data(component), component_query.data, len(component)) != 0 {
                    // The map chain is to give as much context later when ultimately removing the entities
                    append(&entities_to_be_filtered, result.entity_map[entity_index_to_label_map[u32(i)]])
                }
            }
        }

        if component_query.include do component_remove_map[component_query.label] = false
    }

    // Filter all components via the component_remove_map
    component_indices_to_delete := make([dynamic]int)
    for comp_label, remove_comp in component_remove_map {
        if !remove_comp do continue
        delete_key(&result.component_map, comp_label)
        append(&component_indices_to_delete, int(archetype.components_label_match[comp_label]))
    }
    utils.remove_from_dynamic(&result.data, ..component_indices_to_delete[:])

    // Add query entities to filter
    for entity in query.entities do append(&entities_to_be_filtered, archetype.entities[entity])

    // Finally filter entities out

    // Firstly remove from component data
    entity_columns_to_remove := make([dynamic]int, len(entities_to_be_filtered))
    for i in 0..<len(entities_to_be_filtered) {
        entity_columns_to_remove[i] = int(entities_to_be_filtered[i].archetype_column)
        delete_key(&result.entity_map, entities_to_be_filtered[i].name)
    }
    for &comp in result.data do utils.remove_from_dynamic(&comp, ..entity_columns_to_remove[:])


    // And then decrement all the entity columns so that they are in order of one-increments
    // This is valid since we just removed everything in between

    last_column := -1
    for _, &entity in result.entity_map {
        if int(entity.archetype_column) > last_column do entity.archetype_column = u32(last_column + 1)
        last_column = int(entity.archetype_column)
    }

    return
}





/*
/*
    Queries a single components data from the archetype
    Returns data uncopied as compile typed ComponentData
*/
query_component_from_archetype :: proc(archetype: ^Archetype, component_label: string, $T: typeid, entity_labels: ..string) -> (ret: []ComponentData(T), ok: bool) #optional_ok {
    if !(component_label in archetype.components_label_match) {
        dbg.debug_point(dbg.LogLevel.ERROR, "Component does not exist: %s", component_label)
        return
    }

    return query_component_from_archetype_unchecked(archetype, component_label, T, ..entity_labels)
}

/*
    Returns deserialized components given T and x entity labels
    Errors handled internally
*/
@(private)
query_component_from_archetype_unchecked :: proc(archetype: ^Archetype, component_label: string, $T: typeid, entity_labels: ..string) -> (ret: []ComponentData(T), ok: bool) #optional_ok {

    // Get component information
    component_index := archetype.components_label_match[component_label]
    component_info := archetype.component_info.component_infos[component_index]

    if T != component_info.type {
        dbg.debug_point(dbg.LogLevel.ERROR, "Type mismatch with component: %s. Expected type: %v, got: %v", component_label, component_info.type, typeid_of(T))
        return
    }

    components := make([dynamic]ECSComponentData, 0)
    defer delete(components)  // No use after free since components are referencing ECS data

    if len(entity_labels) == 0 {
        // Loop through all entities
        for i := 0; i < int(archetype.n_Entities); i += 1 {
            append(&components, archetype_get_component_data_from_column(archetype, component_label, i))
        }
    }
    else {
        for entity_label in entity_labels {
            entity, entity_exists := archetype.entities[entity_label]
            if !entity_exists {
                dbg.debug_point(dbg.LogLevel.ERROR, "Entity does not exist: %s", entity_label)
                return
            }

            append(&components, archetype_get_component_data_from_column(archetype, component_label, int(entity.archetype_column)))
        }
    }

    ret = components_deserialize(T, ..components[:])
    ok = true
    return
}


// Actions - not sure why these are even needed


    Defining an action a procedure which runs for every entity in the archetype, for a specific component. 
    This standardises and quickens the process of acting a procedure (without any direct return) to entity component data.

    An action should take one component as input, and when using act_on_archetype actions and entities in each query should be treated parallel.

    Honestly there is not much of a reason to use these
    You could just query, and then iterate and act yourself

Action :: #type proc(component: ECSComponentData) -> (ok: bool)

// Single action across all queried entities
act_on_archetype :: proc(archetype: ^Archetype, query: ArchetypeQuery, action: Action) -> (ok: bool) {
    
    entities_to_query := make([dynamic]^Entity, 0, len(query.entities))
    defer delete(entities_to_query)

    if len(query.entities) != 0 {
        for entity_label in query.entities {
            entity, entity_found := archetype.entities[entity_label]
            if !entity_found {
                dbg.debug_point(dbg.LogLevel.ERROR, "Entity not found when querying: %s", entity_label)
                return
            }
            append(&entities_to_query, &entity)
        }
    }
    else {
        for _, &entity in archetype.entities {
            append(&entities_to_query, &entity)
        }
    }

    if len(query.components) != 0 {
        for component_query in query.components {
            comp_index, component_found := archetype.components_label_match[component_query.label]
            if !component_found {
                dbg.debug_point(dbg.LogLevel.ERROR, "Component not found when querying: %s", component_query.label)
                return
            }

            comp_size := archetype.component_info.component_infos[comp_index].size
            ok = single_act_for_entities(archetype, entities_to_query, comp_index, comp_size, component_query.label, component_query.type, action)
        }
    }
    else {
        for _, comp_index in archetype.components_label_match {
            comp_size := archetype.component_info.component_infos[comp_index].size
            comp_info := archetype.component_info.component_infos[comp_index]
            ok = single_act_for_entities(archetype, entities_to_query, comp_index, comp_size, comp_info.label, comp_info.type, action)
        }
    }

    if !ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "An action was not able to be completed")
    }

    ok = true
    return
}

@(private)
single_act_for_entities :: proc(archetype: ^Archetype, entities_to_query: [dynamic]^Entity, comp_index: u32, comp_size: u32, comp_label: string, comp_type: typeid, action: Action) -> (ok: bool) {

    for entity in entities_to_query {
        component: ECSComponentData
        component.label = comp_label 
        component.type = comp_type
        component.data = archetype.components[comp_index][entity.archetype_column:entity.archetype_column + comp_size]

        action(component) or_return
    }

    ok = true
    return
}


MultiAction :: #type proc(components: []ECSComponentData) -> (ok: bool)

act_on_archetype_multiple :: proc(archetype: ^Archetype, query: ArchetypeQuery, action: MultiAction) -> (ok: bool) {
    entities_to_query := make([dynamic]^Entity, 0, len(query.entities))
    defer delete(entities_to_query)

    if len(query.entities) != 0 {
        for entity_label in query.entities {
            entity, entity_found := archetype.entities[entity_label]
            if !entity_found {
                dbg.debug_point(dbg.LogLevel.ERROR, "Entity not found when querying: %s", entity_label)
                return
            }
            append(&entities_to_query, &entity)
        }
    }
    else {
        for _, &entity in archetype.entities {
            append(&entities_to_query, &entity)
        }
    }

    component_indices: [dynamic]u32
    defer delete(component_indices)

    if len(query.components) != 0 {
        component_indices = make([dynamic]u32, len(query.components))
        for component_query, i in query.components {
            comp_index, component_found := archetype.components_label_match[component_query.label]
            if !component_found {
                dbg.debug_point(dbg.LogLevel.ERROR, "Component not found when querying: %s", component_query.label)
                return
            }
            
            component_indices[i] = comp_index
        }
    }
    else {
        component_indices = make([dynamic]u32, len(archetype.components_label_match))
        i := 0
        for _, comp_index in archetype.components_label_match {
            component_indices[i] = comp_index
            i += 1
        }
    }

    ok = multi_act_for_entities(archetype, entities_to_query, component_indices[:], action)
    if !ok {
        dbg.debug_point(dbg.LogLevel.ERROR, "The multi action was not able to be completed")
    }

    ok = true
    return
}

@(private)
multi_act_for_entities :: proc(archetype: ^Archetype, entities_to_query: [dynamic]^Entity, component_indices: []u32, action: MultiAction) -> (ok: bool) {
    components := make([]ECSComponentData, len(component_indices))
    defer delete(components)

    for entity in entities_to_query {
        for comp_index, i in component_indices {
            component_info := archetype.component_info.component_infos[comp_index]
            components[i].label = component_info.label
            components[i].type = component_info.type
            components[i].data = archetype.components[comp_index][entity.archetype_column:entity.archetype_column + component_info.size]
        }

        action(components) or_return
    }

    ok = true
    return
}
*/