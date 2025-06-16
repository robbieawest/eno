package ecs

import "core:mem"
import "core:strings"

// todo review naming it sucks

// Serialized
ComponentData :: struct {
    label: string,
    type: typeid,
    data: []byte
}

FlatComponentsData :: struct {
    component_label_match: map[string]u32,
    component_data: [][]byte
}

// Deserialized
Component :: struct ($T: typeid) {
    label: string,
    data: ^T
}

FlatComponents :: struct ($T: typeid) {
    component_label_match: map[string]u32,
    component_data: []^$T
}



make_component_data :: proc(data_in: ^$T, label: string) -> (component_data: ComponentData) {
    return ComponentData {
        label = label,
        type = T,
        data = transmute([]byte)data_in
    }
}


component_destroy :: proc(component: ComponentData) {
    delete(component.data)
}

components_destroy :: proc(components_data: $T) where
    T == []ComponentData ||
    T == [dynamic]ComponentData
{
    for comp in components_data do delete(comp.data)
    delete(components_data)
}


// Copies everything in input
serialize_component :: proc(component: Component($T), allocator := context.allocator) -> (ret: ComponentData) {
    ret.label = strings.clone(component.label)

    ret.data = make([]byte, size_of(T))
    mem.copy(raw_data(ret.data), component.data, size_of(T))

    return
}

components_serialize :: proc(allocator := context.allocator, $T: typeid, input: ..Component(T)) -> (ret: []ComponentData) {
    ret = make([]ComponentData, len(input))
    
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

component_deserialize:: proc($T: typeid, component: ComponentData, copy := false) -> (component_data: Component(T)) {
    component_data.data = deserialize_component_bytearr(T, component.data)
    component_data.label = component.label
    return
}

components_deserialize_slice :: proc($T: typeid, components_data: ..ComponentData, copy := false) -> (ret: []Component(T)) {
    ret = make([]Component(T), len(components_data))

    for i := 0; i < len(components_data); i += 1 {
        ret[i] = component_deserialize(T, components_data[i])
    }

    return
}

components_deserialize_flat :: proc($T: typeid, components_data: FlatComponentsData, copy := false) -> (ret: FlatComponents(T)) {
    ret.component_label_match = components_data.component_label_match
    ret.component_data = make([]^T, len(components_data.component_data))

    for i := 0; i < len(component_data.component_data); i += 0 {
        ret.component_data[i] = deserialize_component_bytearr(T, components_data.component_data[i])
    }
}
