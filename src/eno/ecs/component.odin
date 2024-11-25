package ecs

import "core:mem"
import "core:reflect"


Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}


// Serializing component data
// Write a serialize_components, deseralize_component, deserialize_components as well

serialize_component :: proc($component: $T, label: string, scene: ^Scene) -> (ret: Component) {
    component_size := size_of(T)

    ret := new(Component)
    ret.data := make([]byte, component_size)
    ret.label = label
    ret.type = T
    
    struct_fields := reflect.struct_fields_zipped(T)
    current_field_ptr := uintptr(raw_data(component))
    component_start_ptr := current_field_ptr
    for field in struct_fields {
        mem.copy()
        ptr_to_field_value := rawptr(current_field_ptr)
        current_field_ptr += field.offset

        byte_index := int(current_field_ptr - component_start_ptr)
        slice_in_ret := ret.data[byte_index:byte_index + field.type.size]
        mem.copy(&slice_in_ret, &ptr_to_field_value, field.type.size)
    }
    
    return
}

