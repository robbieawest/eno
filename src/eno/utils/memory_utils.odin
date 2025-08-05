package utils

import dbg "../debug"

import "core:mem"
import "base:intrinsics"

copy_map :: proc(m: map[$K]$V, allocator := context.allocator) -> (ret: map[K]V) {
    ret = make(map[K]V, len(m), allocator=allocator)
    for k, v in m do ret[k] = v
    return
}

bit_swap :: proc(a: ^$T, b: ^T) {
    a^ ^= b^
    b^ ^= b^
    a^ ^= b^
}


safe_slice :: proc{ d_safe_slice, s_safe_slice }

d_safe_slice :: proc(dyn: $T/[dynamic]$E, #any_int start: int, #any_int end: int, loc := #caller_location) -> ([]E, bool) {
    return s_safe_slice(dyn[:], start, end)
}

s_safe_slice :: proc(slice: $T/[]$E, #any_int start: int, #any_int end: int, loc := #caller_location) -> (sl: []E, ok: bool) {
    if start < 0 || end > len(slice) {
        dbg.log(.ERROR, "Slice is out of range", loc=loc)
        return
    }

    return slice[start:end], true
}

// Dont care enough to add a dyn version
safe_index :: proc(slice: $T/[]$E, #any_int ind: int, loc := #caller_location) -> (elem: ^E, ok: bool) {
    if !index_in_bounds(ind, len(slice)) {
        dbg.log(.ERROR, "Out of bounds index", loc=loc)
        return
    }
    return &slice[ind], true
}


// O(N) memory check where N = num bytes in T
equals :: proc(a: $T, b: T) -> bool {
    a := a; b := b
    return mem.compare_ptrs(&a, &b, type_info_of(T).size) == 0
}


extract_field :: proc(a: $T/[]^$E, $field: string, $field_type: typeid, allocator := context.allocator) -> []^field_type
    where intrinsics.type_has_field(E, field),
          intrinsics.type_field_type(E, field) == field_type {
    ret_dyna := make([dynamic]^field_type, allocator=allocator)

    for elem in a {
        append(&ret_dyna, get_field(elem, field, field_type))
    }
    return ret_dyna[:]
}

get_field :: proc(a: ^$T, $field: string, $field_type: typeid) -> ^field_type
    where intrinsics.type_has_field(T, field),
          intrinsics.type_field_type(T, field) == field_type {
    return cast(^field_type)(offset_of_by_string(T, field) + uintptr(a))
}