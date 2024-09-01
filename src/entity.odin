package eno

import "core:log"
import "core:testing"
import "core:fmt"

MAX_ENTITIES :: 255
_currentEntityIndex: u8 = 0

EntityError :: enum {
    EntityError,
    InitError,
    ComponentError
}

EntityResult :: union {
    ^Entity,
    EntityError
}

Entity :: struct {
    entityId: u8,
    archetypeId: u8
}

initEntity :: proc(archetype: ^EntityArchetype) -> (result: EntityResult) {
    currentEntityIndex := _currentEntityIndex;
    if currentEntityIndex == MAX_ENTITIES {
        log.error("Exceeded MAX_ENTITIES of %v", MAX_ENTITIES);
        result = EntityError.InitError;
        return result;
    }
    _currentEntityIndex += 1;

    archetypeId := u8(len(archetype.entities));
    result = new(Entity)
    entity := result.(^Entity)
    entity.archetypeId = archetypeId
    entity.entityId = currentEntityIndex

    append(&archetype.entities, entity)

    for componentType, &componentData in archetype.entityComponentData {
        append(&componentData, new(type_info_of(componentType)))
    }
    return result
}

ArchetypeResult :: union {
    ^EntityArchetype,
    EntityError
}

EntityArchetype :: struct {
    entities: [dynamic]^Entity,
    entityComponentData: map[typeid][dynamic]^Component
}

initArchetype :: proc(components: ..Component) -> (result: ^EntityArchetype) {
    result = new(EntityArchetype)
    result.entities = make([dynamic]^Entity, 0, 3)
    result.entityComponentData = make(map[typeid][dynamic]^Component)

    for component in components {
        result.entityComponentData[typeid_of(type_of(component))] = make([dynamic]^Component, 0, 3)
    }

    return result;
}


freeArchetype :: proc(archetype: ^EntityArchetype) {
    delete(archetype.entities)
    delete(archetype.entityComponentData)
    free(archetype)
}

@(test)
entityTest :: proc(t: ^testing.T) {
    archetypeTest := new(EntityArchetype)
    defer freeArchetype(archetypeTest)

    entityResult := initEntity(archetypeTest)
    entity, ok := entityResult.(^Entity)
    defer free(entity) //entity is fine to be used with free() since it only contains ints

    testing.expect(t, ok, "Check that initEntity() does not return an error")
    testing.expect_value(t, entity.entityId, 0)
}