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
    data: #soa[dynamic]Component  // SoA structure here allows for easy AoS user access of component data, while being quick for batch operations
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
            component.data = archetype.components[comp_index][entity.archetype_column:entity.archetype_column + comp_size]
            append(&entity_query_result.data, component)
        }
        append(&result, entity_query_result)
    }

    ok = true
    return
}


/*

    Defining an action a procedure which runs for every entity in the archetype, for a specific component. 
    This standardises and quickens the process of acting a procedure (without any direct return) to entity component data.

    An action should take one component as input, and when using act_on_archetype actions and entities in each query should be treated parallel.

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
            ok = act_for_entities(archetype, entities_to_query, comp_index, comp_size, component_query.label, component_query.type, action)
        }
    }
    else {
        for _, comp_index in archetype.components_label_match {
            comp_size := archetype.component_info.component_infos[comp_index].size
            comp_info := archetype.component_info.component_infos[comp_index]
            ok = act_for_entities(archetype, entities_to_query, comp_index, comp_size, comp_info.label, comp_info.type, action)
        }
    }

    if !ok {
        dbg.debug_point(dbg.LogInfo{ msg = "An action was not able to be completed", level = .ERROR})
    }

    ok = true
    return
}

@(private)
act_for_entities :: proc(archetype: ^Archetype, entities_to_query: [dynamic]^Entity, comp_index: u32, comp_size: u32, comp_label: string, comp_type: typeid, action: Action) -> (ok: bool) {

    for entity, i in entities_to_query {
        component: Component
        component.label = comp_label 
        component.type = comp_type
        component.data = archetype.components[comp_index][entity.archetype_column:entity.archetype_column + comp_size]

        action(component) or_return
    }

    ok = true
    return
}

