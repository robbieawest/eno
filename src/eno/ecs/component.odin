package ecs

import "core:mem"

// Does not store much actual data, just points to the archetype memory
Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}
/*
to_component_data :: proc($data: $T) -> []byte {
    transmute()
} */

