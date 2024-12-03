package ecs

import dbg "../debug"

import "core:mem"
import "core:reflect"
import "core:log"
import "base:intrinsics"


// Component represents serialized component data, and ComponentData represented unserialized component_data
// ComponentData is essentially just any with a label

Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}

// Todo: Update usaged of LabelledData in this file with ComponentData
ComponentData :: struct {
    label: string,
    type: typeid,
    data: rawptr
}

make_component_data :: proc(component_in: ^$T, label: string) -> (component_data: ComponentData) {
    return ComponentData{
        label = label,
        type = T,
        data = rawptr(component_in)
    }
}


component_destroy :: proc(component: Component) {
    delete(component.data)
}

// Not sure how I would combine these slice/dynamic methods, definitely missing something here
components_destroy :: proc{ components_destroy_slice, components_destroy_dynamic }

@(private)
components_destroy_slice :: proc(components: $T/[]$E) {
    for comp in components do delete(comp.data)
    delete(components)
}

@(private)
components_destroy_dynamic :: proc(components: $T/[dynamic]$E) {
    for comp in components do delete(comp.data)
    delete(components)
}

/*
components_data_destroy :: proc{ components_data_destroy_slice, components_data_destroy_dynamic }

@(private)
components_data_destroy_slice :: proc(components_data: []ComponentData) {
    for comp in components do delete(comp.data)
    delete(components)
}

@(private)
components_data_destroy_dynamic :: proc(components_data: [dynamic]ComponentData) {
    for comp in components do delete(comp.data)
    delete(components)
}
*/

component_data_destroy :: proc(component_data: ComponentData) {
    free(component_data.data)
}

components_data_destroy :: proc(components_data: $T) where type_of(T) == []ComponentData || type_of(T) == [dynamic]ComponentData {
    for comp in components do delete(comp.data)
    delete(components)
}


// Serializing component data
// Reflection could be slow here, it ultimatey depends on how type_info_of is defined

component_serialize :: proc(component_data: ComponentData) -> (ret: Component) {
    ret.data = make([]byte, size_of(component_data.type))
    ret.label = component_data.label
    ret.type = component_data.type
    
    struct_fields := reflect.struct_fields_zipped(component_data.type)
    component_start := uintptr(component_data.data)
    for field in struct_fields {
        p_Field_data: uintptr = component_start + field.offset
        
        // Insert field data into correct space in ret.data
        // Looking at ret.data with field.offset
        
        mem.copy(&ret.data[field.offset], rawptr(p_Field_data), field.type.size)
    }
    
    return
}

components_serialize :: proc(input: ..ComponentData) -> (ret: []Component) {
    //input := many_input.input
    ret = make([]Component, len(input))
    
    for i := 0; i < len(input); i += 1 {
        ret[i] = component_serialize(input[i])
    }

    return
}


// Deserialization, ret is heap allocated


component_deserialize :: proc(component: Component, allocator := context.allocator) -> (component_data: ComponentData, ok: bool) {
    r_Component_data, err := mem.alloc(size_of(component.type), allocator = allocator)
    if err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogInfo{ msg = "Could not allocate component data in deserialization", level = .ERROR })
        return
    }

    struct_fields := reflect.struct_fields_zipped(component.type)
    for field in struct_fields {
        p_Component_field: uintptr = uintptr(r_Component_data) + field.offset
        mem.copy(rawptr(p_Component_field), &component.data[field.offset], field.type.size)
    }

    component_data.label = component.label
    component_data.type = component.type
    component_data.data = r_Component_data
    ok = true

    return
}

components_deserialize :: proc(components: ..Component, allocator := context.allocator) -> (ret: []ComponentData, ok: bool) {
    ret = make([]ComponentData, len(components))

    for i := 0; i < len(components); i += 1 {
        ret[i] = component_deserialize(components[i], allocator) or_return
    }

    ok = true
    return
}

