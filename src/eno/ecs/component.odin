package ecs

import "core:mem"

// Does not store much actual data, just points to the archetype memory
Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}


to_component_data :: proc(data: any) -> (ret: [dynamic]byte) {
    ret = make([dynamic]byte, size_of(data.id) >> 4)

    data_byte_rep: []byte = transmute([]byte)(data.data)
    mem.copy(ret[:], &data_byte_rep, len(ret))
    return
} 

make_entity_component_data :: proc(data: ..any) -> (ret: [dynamic][]byte) {
    ret = make([dynamic][]byte, len(data))

    for comp_data in data {
        converted := to_component_data(comp_data)
        append(&ret, converted[:])
    }

    return
}
