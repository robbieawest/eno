package ecs


ArchetypeQuery :: struct {
    entities: []string,
    components: []string
}

ArchetypeQueryResult :: struct ($num_entities: u32) {
    data: #soa[num_entities]Component  // SoA structure here allows for easy AoS user access of component data, while being quick for batch operations
}

query_archetype :: proc(archetype: ^Archetype, query: ArchetypeQuery, num_entities: u32) -> (result: ArchetypeQueryResult(num_entities), ok: bool) {
    
}
