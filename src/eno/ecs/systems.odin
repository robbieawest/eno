package ecs

import "core:testing"
import "core:log"
import "core:fmt"


add_entities_of_archetype :: proc(archetype_label: string, n: u8, scene: ^Scene) {

    if CurrentEntity + n > MAX_ENTITIES {
        log.error("MAX_ENTITIES succeded when attempting to add entities to archetype, cancelling attempt")
        return
    }

    //A linear search through archetypes is not bad I don't think
    //The number of archetypes should not be large enough for this to matter
    //Revise if necessary (needs revised actually ignore above)

    archetype: ^Archetype = nil
    for &arch in scene.archetypes {
        if arch.label == archetype_label do archetype = &arch
    }

    new_cap := u8(len(archetype.entities)) + n
    reserve(&archetype.entities, new_cap)

    for i in 0..<n {
        ent := new(Entity)
        defer free(ent)
        ent.entityId = CurrentEntity
        CurrentEntity += 1
        ent.archetypeComponentIndex = u8(len(archetype.entities))
        append(&archetype.entities, ent^)        

        //Components
        for &componentArr in archetype.components {
            firstComponent := componentArr[0] //Is always available due to archetypes not being able to exist without an entity

            newComp := new(Component)
            defer free(newComp)
            append(&componentArr, newComp^)
        }
    }
    
}

SceneSearchQuery :: struct {
    archetypeLabelQueries: []string,
    componentLabelQueries: []string, //receive all of these components from all of the queried archetypes
    nEntities: u8, //Number of entities,
    entity: ^Entity
}

// Allocates a search query on heap
search_query :: proc(archLabels: []string, compLabels: []string, nEntities: u8, entity: ^Entity = nil) -> (result: ^SceneSearchQuery) {
    result = new(SceneSearchQuery)
    result.archetypeLabelQueries = archLabels
    result.componentLabelQueries = compLabels
    result.nEntities = nEntities
    result.entity = entity
    return result
}

QueryResult :: map[string]map[string][]Component
search_scene :: proc(scene: ^Scene, query: SceneSearchQuery) -> (result: QueryResult) {
    //No input sanitization because lazy as shit ToDo
    result = make(QueryResult)

    for archetypeLabel in query.archetypeLabelQueries {
        archetype: ^Archetype = &scene.archetypes[scene.archetypeLabelMatch[archetypeLabel]]
     //   result[archetypeLabel] =  todo this
        for componentLabel in query.componentLabelQueries {
            componentList: ^[dynamic]Component = &archetype.components[archetype.componentLabelMatch[componentLabel]]
            lowerBounds: u8 = 0
            upperBounds: u8 = query.nEntities + 1
            if query.entity != nil {
                lowerBounds = query.entity.archetypeComponentIndex
                upperBounds = lowerBounds + 1
            }

            result[archetypeLabel][componentLabel] = componentList[lowerBounds:upperBounds]
        }
    }

    return result
}

@(test)
search_test :: proc(T: ^testing.T) {

    scene: ^Scene = init_scene_empty()
    defer destroy_scene(scene)

    numeric_components := [2]LabelledComponent{ LabelledComponent { "int", 5 }, LabelledComponent { "float", 12.2 }}
    archetype := init_archetype("testArch", numeric_components[:])

    add_arch_to_scene(scene, archetype) //free's top level archetype definition, could just do add_arch_to_scene(scene, init_archetype(...))
    add_entities_of_archetype("testArch", 3, scene)

    archOperands := [1]string{"testArch"}
    compOperands := [1]string{"int"}
    query := search_query(archOperands[:], compOperands[:], 3, nil)
    defer free(query)
    result: QueryResult = search_scene(scene, query^)
    log.infof("query result: %v", result)
    fmt.println("break")
}

