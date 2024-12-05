package ecs

import dbg "../debug"

import "core:fmt"


ComponentQuery :: struct {
    label: string,
    type: typeid
}


ArchetypeQuery :: struct {
    entities: []string,
    components: []ComponentQuery
}


ArchetypeQueryResult :: [dynamic]EntityQueryResult


EntityQueryResult :: struct {
    data: #soa[dynamic]Component
}


query_archetype :: proc(archetype: ^Archetype, query: ArchetypeQuery) -> (result: ArchetypeQueryResult, ok: bool) {

    query_all_entities := len(query.entities) == 0
    n_query_entities := query_all_entities ? archetype.n_Entities : u32(len(query.entities))
    
    query_all_components := len(query.components) == 0
    n_query_components := query_all_components ? archetype.n_Components : u32(len(query.components))

    entities_to_query := make([dynamic]^Entity, n_query_entities)
    defer delete(entities_to_query)

    for entity_label in query.entities {
        entity, entity_found := archetype.entities[entity_label]
        if !entity_found {
            dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Entity not found when querying: %s", entity_label), level = .ERROR })
            return
        }
        append(&entities_to_query, &entity)
    }

    
    for component_query in query.components {
        comp_index, component_found := archetype.components_label_match[component_query.label]
        if !component_found {
            dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Component not found when querying: %s", component_query.label), level = .ERROR })
            return
        }

        comp_size := archetype.component_info.component_infos[comp_index].size

        entity_query_result: EntityQueryResult
        for entity in entities_to_query {
            component: Component
            component.label = component_query.label
            component.type = component_query.type
            component.data = archetype.components[comp_index][entity.archetype_column:entity.archetype_column + comp_size]  // Smells bad
            append(&entity_query_result.data, component)
        }
        append(&result, entity_query_result)
    }

    ok = true
    return
}

/*
    Queries a single components data from the archetype
    Returns data uncopied as compile typed ComponentData
*/
query_component_from_archetype_checked :: proc(archetype: ^Archetype, component_label: string, $T: typeid, entity_labels: ..string) -> (ret: []ComponentData(T), ok: bool) {
    if !component_label in archetype.components_label_match {
        dbg.debug_point(dbg.LogInfo { msg = fmt.aprintf("Component does not exist: %s", component_label), level = .ERROR })
        return
    }

    return query_component_from_archetype_unchecked(archetype, component_label, T, entity_labels)
}

@(private)
query_component_from_archetype_unchecked :: proc(archetype: ^Archetype, component_label: string, $T: typeid, entity_labels: ..string) -> (ret: []ComponentData(T), ok: bool) {

    // Get component information
    component_index := archetype.components_label_match[component_label]
    component_info := archetype.component_info.component_infos[component_index]

    if T != component_info.type {
        dbg.debug_point(dbg.LogInfo {
            msg = fmt.aprintf("Type mismatch with component: %s. Expected type: %v, got: %v", component_label, component_info.type, T),
            level = .ERROR
        })
        return
    }

    components := make([dynamic]Component, 0)
    defer delete(components)  // No use after free since components are referencing ECS data

    if len(entity_labels) == 0 {
        // Loop through all entities
        for i := 0; i < archetype.n_Entities; i += 1 {
            append(&components, archetype_get_component_data_from_column(archetype, component_label, i))
        }
    }
    else {
        for entity_label in entity_labels {
            entity, entity_exists := archetype.entities[entity_label]
            if !entity_exists {
                dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Entity does not exist: %s", entity_label), level = .ERROR })
                return
            }

            append(&components, archetype_get_component_data_from_column(archetype, component_label, entity.archetype_column))
        }
    }

    ret = components_deserialize(T, ..components[:])
    ok = true
    return
}


/*

    Defining an action a procedure which runs for every entity in the archetype, for a specific component. 
    This standardises and quickens the process of acting a procedure (without any direct return) to entity component data.

    An action should take one component as input, and when using act_on_archetype actions and entities in each query should be treated parallel.

    Honestly there is not much of a reason to use these
    You could just query, and then iterate and act yourself
*/

Action :: #type proc(component: Component) -> (ok: bool)

// Single action across all queried entities
act_on_archetype :: proc(archetype: ^Archetype, query: ArchetypeQuery, action: Action) -> (ok: bool) {
    
    entities_to_query := make([dynamic]^Entity, 0, len(query.entities))
    defer delete(entities_to_query)

    if len(query.entities) != 0 {
        for entity_label in query.entities {
            entity, entity_found := archetype.entities[entity_label]
            if !entity_found {
                dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Entity not found when querying: %s", entity_label), level = .ERROR })
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
                dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Component not found when querying: %s", component_query.label), level = .ERROR })
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
        dbg.debug_point(dbg.LogInfo{ msg = "An action was not able to be completed", level = .ERROR})
    }

    ok = true
    return
}

@(private)
single_act_for_entities :: proc(archetype: ^Archetype, entities_to_query: [dynamic]^Entity, comp_index: u32, comp_size: u32, comp_label: string, comp_type: typeid, action: Action) -> (ok: bool) {

    for entity in entities_to_query {
        component: Component
        component.label = comp_label 
        component.type = comp_type
        component.data = archetype.components[comp_index][entity.archetype_column:entity.archetype_column + comp_size]

        action(component) or_return
    }

    ok = true
    return
}


MultiAction :: #type proc(components: []Component) -> (ok: bool)

act_on_archetype_multiple :: proc(archetype: ^Archetype, query: ArchetypeQuery, action: MultiAction) -> (ok: bool) {
    entities_to_query := make([dynamic]^Entity, 0, len(query.entities))
    defer delete(entities_to_query)

    if len(query.entities) != 0 {
        for entity_label in query.entities {
            entity, entity_found := archetype.entities[entity_label]
            if !entity_found {
                dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Entity not found when querying: %s", entity_label), level = .ERROR })
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
                dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("Component not found when querying: %s", component_query.label), level = .ERROR })
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
        dbg.debug_point(dbg.LogInfo{ msg = "The multi action was not able to be completed", level = .ERROR})
    }

    ok = true
    return
}

@(private)
multi_act_for_entities :: proc(archetype: ^Archetype, entities_to_query: [dynamic]^Entity, component_indices: []u32, action: MultiAction) -> (ok: bool) {
    components := make([]Component, len(component_indices))
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
