package ecs

import dbg "../debug"

import "core:mem"
import "core:reflect"
import "core:log"
import "base:intrinsics"


Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}


component_destroy :: proc(component: Component) {
    delete(component.data)
}

components_destroy :: proc(components: $T) where intrinsics.type_is_slice(T) || intrinsics.type_is_dynamic_array(T) {
    for comp in components do delete(comp.data)
    delete(components)
}


// Serializing component data

component_serialize :: proc($T: typeid, component: ^T, label: string) -> (ret: Component) {
    ret.data = make([]byte, size_of(T))
    ret.label = label
    ret.type = T
    
    struct_fields := reflect.struct_fields_zipped(T)
    component_start := uintptr(component)
    for field in struct_fields {
        p_Field_data: uintptr = component_start + field.offset
        
        // Insert field data into correct space in ret.data
        // Looking at ret.data with field.offset
        
        mem.copy(&ret.data[field.offset], rawptr(p_Field_data), field.type.size)
    }
    
    return
}

LabelledData :: struct($T: typeid) { data: ^T, label: string }
components_serialize :: proc($T: typeid, input: []LabelledData(T)) -> (ret: []Component) {
    //input := many_input.input
    ret = make([]Component, len(input))
    
    for i := 0; i < len(input); i += 1 {
        ret[i] = component_serialize(T, input[i].data, input[i].label)
    }

    return
}


// Deserialization, ret is heap allocated

component_deserialize :: proc(component: ^Component, allocator := context.allocator) -> (ret: any) {
    return component_data_deserialize(component.data, component.type, allocator)
}

component_data_deserialize :: proc(component_data: []byte, T: typeid, allocator := context.allocator) -> (ret: any) {
    component, err := mem.alloc(size_of(T), allocator = allocator)
    if err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogInfo{ msg = "Could not allocate component data in deserialization", level = .ERROR })
        return
    }

    struct_fields := reflect.struct_fields_zipped(T)
    for field in struct_fields {
        p_Component_field: uintptr = uintptr(component) + field.offset
        mem.copy(rawptr(p_Component_field), &component_data[field.offset], field.type.size)
    }

    return any {
        component,
        T
    }
}



