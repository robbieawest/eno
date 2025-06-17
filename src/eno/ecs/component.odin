package ecs

import dbg "../debug"

import "core:mem"
import "core:strings"


// Serialized
ECSComponentData :: struct {
    label: string,
    type: typeid,
    data: []byte
}

destroy_ecs_component_data :: proc(component: ECSComponentData) {
    delete(component.label)
    delete(component.data)
}

ECSMatchedComponentData :: struct {
    component_label_match: map[string]u32,
    component_data: [][]byte
}

// Deserialized
ComponentData :: struct ($T: typeid) {
    label: string,
    data: ^T
}

MatchedComponentData :: struct ($T: typeid) {
    component_label_match: map[string]u32,
    component_data: []^$T
}


// Serialization and deserialization

// Copies everything in input
serialize_component :: proc(component: ComponentData($T), allocator := context.allocator) -> (ret: ECSComponentData) {
    ret.label = strings.clone(component.label)

    ret.data = make([]byte, size_of(T))
    mem.copy(raw_data(ret.data), component.data, size_of(T))

    return
}

components_serialize :: proc(allocator := context.allocator, $T: typeid, input: ..ComponentData(T)) -> (ret: []ECSComponentData) {
    ret = make([]ECSComponentData, len(input))
    
    for i := 0; i < len(input); i += 1 {
        ret[i] = serialize_component(input[i])
    }

    return
}


@(private)
deserialize_component_bytearr :: proc($T: typeid, bytearr: []byte, copy := false) -> (out: ^T) {
    new_data: ^T = cast(^T)raw_data(bytearr)
    if copy do mem.copy(out, new_data, size_of(T))
    else do out = new_data
    return
}

component_deserialize:: proc($T: typeid, component: ECSComponentData, copy := false) -> (component_data: ComponentData(T)) {
    data: ^T = deserialize_component_bytearr(T, component.data)
    component_data = ComponentData(T){ label = component.label, data = data }
    return
}

components_deserialize :: proc{ components_deserialize_slice, components_deserialize_matched }

components_deserialize_slice :: proc($T: typeid, components_data: ..ECSComponentData, copy := false) -> (ret: []ComponentData(T)) {
    ret = make([]ComponentData(T), len(components_data))

    for i := 0; i < len(components_data); i += 1 {
        ret[i] = component_deserialize(T, components_data[i])
    }

    return
}

components_deserialize_matched :: proc($T: typeid, components_data: ECSMatchedComponentData, copy := false) -> (ret: MatchedComponentData(T)) {
    ret.component_label_match = components_data.component_label_match
    ret.component_data = make([]^T, len(components_data.component_data))

    for i := 0; i < len(component_data.component_data); i += 0 {
        ret.component_data[i] = deserialize_component_bytearr(T, components_data.component_data[i])
    }
}
