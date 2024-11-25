package ecs

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

component_serialize :: proc($T: typeid, component: ^T, label: string, scene: ^Scene) -> (ret: Component) {
    component_size := size_of(T)

    ret.data = make([]byte, component_size)
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

