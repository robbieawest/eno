package ecs

import dbg "../debug"
import "../model"
import "../gpu"

import "core:mem"
import "core:reflect"
import "core:log"
import "base:intrinsics"


/*
   Component represents serialized component data, and ComponentData represented unserialized component_data
   ComponentData is essentially just any with a label

   Destruction utilities are given for this type.
*/

Component :: struct {
    label: string,
    type: typeid,
    data: []byte
}

/* 
   Represents serialized component data
   This should only be used if you are working solely with a Component and no compile-time type
   Although this is Untyped, it does contain the runtime type as the type field.

   No utilities are given to destroy deserialized component data, for this compile-time type
   case, this is not expected usage, since it is directly referencing ECS data. 
*/
ComponentDataUntyped :: struct {
    label: string,
    type: typeid,
    data: rawptr
}

/*
   Represents deserialized component data
   This, and associated procedures, should be used if you have the compile-time type 
   No utilities are given to destroy deserialized component data, for this compile-time type
   case, this is not expected usage, since it is directly referencing ECS data. 
*/
ComponentData :: struct ($T: typeid) {
    label: string,
    data: ^T
}


/* _s postfix refers to stack allocated */
make_component_data_untyped_s :: proc(component_in: ^$T, label: string, allocator := context.allocator) -> (component_data: ComponentDataUntyped) {
    return ComponentDataUntyped {
        label = label,
        type = T,
        data = rawptr(component_in)
    }
}

/* _s postfix refers to stack allocated */
make_component_data_s :: proc(component_in: ^$T, label: string) -> (component_data: ComponentData(T)) {
    return ComponentData(T) {
        label = label,
        data = component_in
    }
}

make_component_data_untyped :: proc(component_in: ^$T, label: string, allocator := context.allocator) -> (component_data: ^ComponentDataUntyped) {
    component_data = new(ComponentDataUntyped, allocator)
    component_data.label = label
    component_data.data = rawptr(component_in)
    component_data.type = T
}

make_component_data :: proc(component_in: ^$T, label: string, allocator := context.allocator) -> (component_data: ^ComponentData(T)) {
    component_data = new(ComponentData(T), allocator)
    component_data.label = label
    component_data.data = component_in
    return
}


component_destroy :: proc(component: Component) {
    delete(component.data)
}

components_destroy :: proc(components_data: $T) where
    T == []Component ||
    T == [dynamic]Component
{
    for comp in components_data do delete(comp.data)
    delete(components_data)
}



// Serializing component data
// Reflection could be slow here, it ultimately depends on how type_info_of is defined

// ToDo: Give allocator option

component_serialize :: proc { component_serialize_untyped, component_serialize_typed }

component_serialize_untyped :: proc(component_data: ComponentDataUntyped, allocator := context.allocator) -> (ret: Component) {
    log.infof("component data: %#v, type size: %d, type info: %v", component_data, size_of(component_data.type), type_info_of(component_data.type).size)
    log.infof("mesh: %d, draw comp: %#v", size_of(model.Mesh), type_info_of(gpu.DrawProperties).size)
    ret.data = make([]byte, type_info_of(component_data.type).size)
    ret.label = component_data.label
    ret.type = component_data.type
    
    struct_fields := reflect.struct_fields_zipped(component_data.type)
    component_start := uintptr(component_data.data)
    for field in struct_fields {
        p_Field_data: uintptr = component_start + field.offset
        
        // Insert field data into correct space in ret.data
        // Looking at ret.data with field.offset
        log.infof("field: %#v, field_size: %d", field, field.type.size)
        mem.copy(&ret.data[field.offset], rawptr(p_Field_data), field.type.size)
    }
    
    return
}

component_serialize_typed :: proc($T: typeid, component_data: ComponentData(T), allocator := context.allocator) -> (ret: Component) {
    ret.data = make([]byte, size_of(T))
    ret.label = component_data.label
    ret.type = T
    
    struct_fields := reflect.struct_fields_zipped(T)
    component_start := uintptr(component_data.data)
    for field in struct_fields {
        p_Field_data: uintptr = component_start + field.offset
        
        // Insert field data into correct space in ret.data
        // Looking at ret.data with field.offset
        
        mem.copy(&ret.data[field.offset], rawptr(p_Field_data), field.type.size)
    }
    
    return
}


components_serialize_untyped :: proc(allocator := context.allocator, input: ..ComponentDataUntyped) -> (ret: []Component) {
    ret = make([]Component, len(input))
    
    for i := 0; i < len(input); i += 1 {
        ret[i] = component_serialize_untyped(input[i])
    }

    return

}

components_serialize :: proc(allocator := context.allocator, $T: typeid, input: ..ComponentData(T)) -> (ret: []Component) {
    ret = make([]Component, len(input))
    
    for i := 0; i < len(input); i += 1 {
        ret[i] = component_serialize(T, input[i])
    }

    return
}

/*
   Component deserialization
   Use this procedure over the individual copy/no copy procedures
   Pass in an allocator as the second argument to copy

   Returns runtime typed (defined untyped) component data
*/
component_deserialize_untyped :: proc{ component_deserialize_untyped_inner, component_deserialize_copy_untyped}

@(private)
component_deserialize_untyped_inner :: proc(component: Component) -> (component_data: ComponentDataUntyped, ok: bool) {
    ok = true
    component_data.type = component.type
    component_data.data = rawptr(&component.data[0])
    component_data.label = component.label
    return
}

@(private)
component_deserialize_copy_untyped :: proc(component: Component, allocator: mem.Allocator) -> (component_data: ComponentDataUntyped, ok: bool) {
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


/*
   Component deserialization
   Use this procedure over the individual copy/no copy procedures
   Pass in an allocator as the second argument to copy

   Returns compile-time typed (defined typed) component data
*/
component_deserialize :: proc{ component_deserialize_typed, component_deserialize_copy_typed }

@(private)
component_deserialize_typed :: proc($T: typeid, component: Component) -> (component_data: ComponentData(T), ok: bool) {
    ok = true
    component_data.data = cast(^T)&component.data[0]
    component_data.label = component.label
    return
}

@(private)
component_deserialize_copy_typed :: proc($T: typeid, component: Component, allocator := context.allocator) -> (component_data: ComponentData(T), ok: bool) {
    r_Component_data, err := mem.alloc(size_of(T), allocator = allocator)
    if err != mem.Allocator_Error.None {
        dbg.debug_point(dbg.LogInfo{ msg = "Could not allocate component data in deserialization", level = .ERROR })
        return
    }

    struct_fields := reflect.struct_fields_zipped(T)
    for field in struct_fields {
        p_Component_field: uintptr = uintptr(r_Component_data) + field.offset
        mem.copy(rawptr(p_Component_field), &component.data[field.offset], field.type.size)
    }

    component_data.label = component.label
    component_data.data = cast(^T)r_Component_data
    ok = true

    return
}

//components_deserialize :: proc{ components_deserialize_typed, components_deserialize_copy_typed } // Odin can't seem to differentiate between the two
components_deserialize :: proc{ components_deserialize_typed }

components_deserialize_typed :: proc($T: typeid, components: ..Component) -> (ret: []ComponentData(T), ok: bool) {
    ret = make([]ComponentData(T), len(components))

    for i := 0; i < len(components); i += 1 {
        ret[i] = component_deserialize_typed(T, components[i]) or_return
    }

    ok = true
    return
}

/*
components_deserialize_copy_typed :: proc($T: typeid, allocator: mem.Allocator, components: ..Component) -> (ret: []ComponentData(T), ok: bool) {
    ret = make([]ComponentData(T), len(components))

    for i := 0; i < len(components); i += 1 {
        ret[i] = component_deserialize_copy_typed(T, components[i], allocator) or_return
    }

    ok = true
    return
}
*/


components_deserialize_untyped :: proc{ components_deserialize_untyped_inner, components_deserialize_copy_untyped }

components_deserialize_untyped_inner :: proc(components: ..Component) -> (ret: []ComponentDataUntyped, ok: bool) {
    ret = make([]ComponentDataUntyped, len(components))

    for i := 0; i < len(components); i += 1 {
        ret[i] = component_deserialize_untyped(components[i]) or_return
    }

    ok = true
    return
}

components_deserialize_copy_untyped :: proc(allocator: mem.Allocator, components: ..Component) -> (ret: []ComponentDataUntyped, ok: bool) {
    ret = make([]ComponentDataUntyped, len(components))

    for i := 0; i < len(components); i += 1 {
        ret[i] = component_deserialize_copy_untyped(components[i], allocator) or_return
    }

    ok = true
    return
}
