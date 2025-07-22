package ecs

import dbg "../debug"

import "core:mem"
import "core:slice"
import "core:strings"

import "base:intrinsics"
import "core:log"

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

make_ecs_component_data :: proc{ make_ecs_component_data_raw, make_ecs_component_data_typed }

// Copies everything!
make_ecs_component_data_raw :: proc(label: string, type: typeid, data: []byte) -> ECSComponentData {
    return {strings.clone(label), type, slice.clone(data) }
}

// Copies everything!
make_ecs_component_data_typed :: proc(label: string, type: typeid, data: $T) -> ECSComponentData {
    return {strings.clone(label), type, serialize_data(data) }
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


// Serialization and deserialization

serialize_data :: proc{ serialize_data_pointer, serialize_data_raw }

serialize_data_pointer :: proc(data: ^$T, copy := false) -> []byte {
    data := transmute([]byte)mem.Raw_Slice{ data, type_info_of(T).size }
    return copy ? slice.clone(data) : data
}

serialize_data_raw :: proc(data: $T) -> []byte
    where !intrinsics.type_is_pointer(T) {
    // Must copy
    data := data
    return slice.clone(transmute([]byte)mem.Raw_Slice{ &data, type_info_of(T).size })
}


// Copies everything in input
serialize_component :: proc(component: ComponentData($T), copy := false, allocator := context.allocator) -> (ret: ECSComponentData) {
    ret.label = strings.clone(component.label)
    ret.data = serialize_data(component.data, copy)
    return
}

components_serialize :: proc(allocator := context.allocator, $T: typeid, input: ..ComponentData(T)) -> (ret: []ECSComponentData) {
    ret = make([]ECSComponentData, len(input))
    
    for i := 0; i < len(input); i += 1 {
        ret[i] = serialize_component(input[i])
    }

    return
}


component_deserialize_raw :: proc($T: typeid, bytearr: []byte, copy := false, loc := #caller_location) -> (out: ^T, ok: bool) {
    if len(bytearr) != type_info_of(T).size {
        dbg.log(.ERROR, "Size of component type does not match given data", loc=loc)
        return
    }

    new_data: ^T = cast(^T)raw_data(bytearr)
    if copy do mem.copy(out, new_data, size_of(T))
    else do out = new_data

    ok = true
    return
}

component_deserialize :: proc($T: typeid, component: ECSComponentData, copy := false, loc := #caller_location) -> (component_data: ComponentData(T), ok: bool) {
    data: ^T = component_deserialize_raw(T, component.data, copy, loc) or_return
    component_data = ComponentData(T){ label = component.label, data = data }

    ok = true
    return
}

components_deserialize_raw :: proc{ components_deserialize_raw_slice, components_deserialize_raw_dyna }

components_deserialize_raw_slice :: proc($T: typeid, components_data: [][]byte, copy := false, loc := #caller_location) -> (ret: []^T, ok: bool) {
    ret = make([]^T, 0, len(components_data))
    for comp_data in components_data do append(&ret, component_deserialize_raw(T, comp_data, copy, loc) or_return)

    ok = true
    return
}

components_deserialize_raw_dyna :: proc($T: typeid, components_data: [dynamic][dynamic]byte, copy := false, loc := #caller_location) -> (ret: []^T, ok: bool) {
    ret = make([]^T, len(components_data))
    for comp_data, i in components_data do ret[i] = component_deserialize_raw(T, comp_data[:], copy, loc) or_return

    ok = true
    return
}


components_deserialize :: proc($T: typeid, components_data: ..ECSComponentData, copy := false, loc := #caller_location) -> (ret: []ComponentData(T), ok: bool) {
    ret = make([]ComponentData(T), len(components_data))

    for i := 0; i < len(components_data); i += 1 {
        ret[i] = component_deserialize(T, components_data[i], copy, loc) or_return
    }

    ok = true
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