package ecs

import dbg "../debug"

import "core:mem"
import "core:slice"
import "core:strings"

ComponentTemplate :: struct {
    label: string,
    type: typeid
}

// Serialized
ECSComponentData :: struct {
    label: string,
    type: typeid,
    data: []byte
}

// Copies everything!
make_ecs_component_data:: proc(label: string, type: typeid, data: []byte) -> ECSComponentData {
    return {strings.clone(label), type, slice.clone(data) }
}


destroy_ecs_component_data :: proc(component: ECSComponentData) {
    delete(component.label)
    delete(component.data)
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

serialize_data :: proc(data: ^$T, copy := false) -> []byte {
    data := transmute([]byte)mem.Raw_Slice{ data, size_of(T) }
    return copy ? slice.clone(data) : data
}

// Copies everything in input
serialize_component :: proc(component: ComponentData($T), allocator := context.allocator) -> (ret: ECSComponentData) {
    ret.label = strings.clone(component.label)
    ret.data = serialize_data(component.data)
    return
}

components_serialize :: proc(allocator := context.allocator, $T: typeid, input: ..ComponentData(T)) -> (ret: []ECSComponentData) {
    ret = make([]ECSComponentData, len(input))
    
    for i := 0; i < len(input); i += 1 {
        ret[i] = serialize_component(input[i])
    }

    return
}


component_deserialize_raw :: proc($T: typeid, bytearr: []byte, copy := false) -> (out: ^T) {
    new_data: ^T = cast(^T)raw_data(bytearr)
    if copy do mem.copy(out, new_data, size_of(T))
    else do out = new_data
    return
}

component_deserialize:: proc($T: typeid, component: ECSComponentData, copy := false) -> (component_data: ComponentData(T)) {
    data: ^T = component_deserialize_raw(T, component.data)
    component_data = ComponentData(T){ label = component.label, data = data }
    return
}

components_deserialize_raw :: proc($T: typeid, components_data: $B, copy := false) -> (ret: []^T)
    where B == [dynamic][dynamic]byte || B == [][]byte {
    ret = make([]^T, 0, len(components_data))
    for comp_data in components_data do append(&ret, component_deserialize_raw(T, comp_data, copy))
    return
}

components_deserialize :: proc($T: typeid, components_data: ..ECSComponentData, copy := false) -> (ret: []ComponentData(T)) {
    ret = make([]ComponentData(T), len(components_data))

    for i := 0; i < len(components_data); i += 1 {
        ret[i] = component_deserialize(T, components_data[i])
    }

    return
}

/*
components_deserialize_matched :: proc($T: typeid, components_data: ECSMatchedComponentData, copy := false) -> (ret: MatchedComponentData(T)) {
    ret.component_label_match = components_data.component_label_match
    ret.component_data = make([]^T, len(components_data.component_data))

    for i := 0; i < len(component_data.component_data); i += 0 {
        ret.component_data[i] = deserialize_component_bytearr(T, components_data.component_data[i])
    }
}
*/