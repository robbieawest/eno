package ecs

import dbg "../debug"

import "core:mem"
import "core:reflect"
import "core:log"


Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}

component_destroy :: proc(component: ^Component) {
    delete(component.data)
}


// Serializing component data
// Write a serialize_components, deseralize_component, deserialize_components as well

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


// Deserialization, ret is heap allocated
// maybe give allocator option

component_deserialize :: proc(component: ^Component) -> (ret: any) {
    return component_data_deserialize(component.data, component.type)
}

component_data_deserialize :: proc(component_data: []byte, T: typeid) -> (ret: any) {
    component, err := mem.alloc(size_of(T))
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



