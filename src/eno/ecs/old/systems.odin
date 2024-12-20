package old 

import "core:testing"
import "core:log"
import "core:fmt"
import "core:mem"
import "core:slice"


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


SearchQuery :: struct {
    archetypeLabelQueries: []string,
    componentLabelQueries: []string, //receive all of these components from all of the queried archetypes
    nEntities: u8, //Number of entities,
    entity: ^Entity
}


// Allocates a search query on heap
search_query :: proc(archLabels: []string, compLabels: []string, nEntities: u8, entity: ^Entity = nil) -> (result: ^SearchQuery) {
    result = new(SearchQuery)
    result.archetypeLabelQueries = archLabels
    result.componentLabelQueries = compLabels
    result.nEntities = nEntities
    result.entity = entity
    return result
}


QueryResult :: map[string]map[string][]Component
destroy_query_result :: proc(result: QueryResult) {
    for key, &value in result do delete(value)
    delete(result)
}


search_scene :: proc(scene: ^Scene, query: ^SearchQuery) -> (result: QueryResult) {
    //No input sanitization because lazy as shit ToDo
    result = make(QueryResult)

    // If archetype labels is empty in query search all archetypes
    no_archetype_labels_buffer := make([dynamic]string, len(scene.archetypes))
    defer delete(no_archetype_labels_buffer)

    if len(query.archetypeLabelQueries) == 0 {
        log.info("in here")
        for archetype in scene.archetypes {
            append(&no_archetype_labels_buffer, archetype.label)
        }
        query.archetypeLabelQueries = no_archetype_labels_buffer[:]
    }
    log.infof("past, %#v", query.archetypeLabelQueries)

    
    for archetypeLabel in query.archetypeLabelQueries {
        log.infof("label: %s", archetypeLabel)

        archetype: ^Archetype = &scene.archetypes[scene.archetypeLabelMatch[archetypeLabel]]
        componentMap := make(map[string][]Component)
        for componentLabel in query.componentLabelQueries {
            log.infof("component: %s", componentLabel)
            log.infof("component map before: %#v", componentMap)

            lower_bounds: u8 = 0
            upper_bounds: u8 = query.nEntities
            if query.entity != nil {
                lower_bounds = query.entity.archetypeComponentIndex
                upper_bounds = lower_bounds + 1
            }
            
            componentList: [dynamic]Component = archetype.components[archetype.componentLabelMatch[componentLabel]]
            slice_upper_bounds := min(upper_bounds, u8(len(componentList)))

            
            componentMap[componentLabel] = componentList[lower_bounds:slice_upper_bounds]
            log.infof("component map: %#v", componentMap)
        }
        log.info("out")
        log.infof("component map: %#v", componentMap)
        log.infof("result before: %#v", result)
        result[archetypeLabel] = componentMap
        log.info("result after: %#v", result)
        log.info("out2")
    }
    log.info("jiji")
    log.infof("hey: result: %#v", result)

    return result
}


set_components :: proc(query: ^SearchQuery, components: [][][]Component, scene: ^Scene) -> (result: QueryResult) {
    //searches and then sets, not the most efficient so to speak
    result = search_scene(scene, query)
    i := 0
    for _, &componentMap in result {
        j := 0
        for _, &componentList in componentMap {
            componentsToSet := &components[i][j]
            for k in 0..<len(componentsToSet) do componentList[k] = componentsToSet[k]
            j += 1
        }
        i += 1
    }
    return result
}


@(test)
search_test :: proc(T: ^testing.T) {

    scene: ^Scene = init_scene_empty()
    defer destroy_scene(scene)

    numeric_components := []LabelledComponent{ LabelledComponent { "int", 5 }, LabelledComponent { "float", 12.2 }}
    archetype := init_archetype("testArch", numeric_components)

    add_arch_to_scene(scene, archetype) //free's top level archetype definition, could just do add_arch_to_scene(scene, init_archetype(...))
    add_entities_of_archetype("testArch", 3, scene)

    archOperands := []string{"testArch"}
    compOperands := []string{"int", "float"}
    query := search_query(archOperands[:], compOperands, 3, nil)
    defer free(query)

    result: QueryResult = search_scene(scene, query)
    defer destroy_query_result(result)

    log.infof("query result: %v", result)
    fmt.println("break")
}


@(test)
set_test :: proc(t: ^testing.T) {
    scene: ^Scene = init_scene_empty()
    defer destroy_scene(scene)

    numeric_components := []LabelledComponent{ LabelledComponent { "int", 5 }, LabelledComponent { "float", 12.2 }}
    archetype := init_archetype("testArch", numeric_components)

    add_arch_to_scene(scene, archetype) //free's top level archetype definition, could just do add_arch_to_scene(scene, init_archetype(...))
    add_entities_of_archetype("testArch", 3, scene)

    archOperands := []string{"testArch"}
    compOperands := []string{"int", "float"}
    query := search_query(archOperands, compOperands, 3, nil)
    defer free(query)

    updated_components := [][][]Component{ [][]Component{ []Component{ 19, 32 }, []Component {13.5} }} //Not very nice but kind of necessary
    log.infof("scene before set: %v", scene)

    result: QueryResult = set_components(query, updated_components[:], scene)
    defer destroy_query_result(result)
    log.infof("scene after set: %v", scene)
}
