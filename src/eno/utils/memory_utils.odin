package utils

import dbg "../debug"

import "core:mem"
import "base:intrinsics"
import "base:runtime"

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


to_bytes :: proc(ptr: ^$T) -> []byte {
    return (cast([^]byte)ptr)[:type_info_of(T).size]
}

map_to_bytes :: proc(m: map[$K]$V, bytes: ^[dynamic]byte) {
    for k, v in m {
        key := k; value := v
        append_elems(bytes, ..to_bytes(&key))
        append_elems(bytes, ..to_bytes(&value))
    }
}

flip_bitset :: proc(bitset: $T/bit_set[$E; $B]) -> (flipped: T) {
    return transmute(T)(!(transmute(B)bitset))
}

map_keys :: proc(m: $M/map[$K]$V, allocator := context.allocator) -> (keys: []K, ok: bool) {
    keys_s, err := make(type_of(keys), len(m), allocator)
    if err != nil {
        dbg.log(.ERROR, "Allocator error")
        return
    }

    i := 0
    for key in m {
        keys_s[i] = key
        i += 1
    }
    return keys_s, true
}

map_values :: proc(m: $M/map[$K]$V, allocator := context.allocator) -> (values: []V, ok: bool) {
    values_s, err := make(type_of(values), len(m), allocator)
    if err != nil {
        dbg.log(.ERROR, "Allocator error")
        return
    }

    i := 0
    for _, value in m {
        values_s[i] = value
        i += 1
    }
    return values_s, true
}


cast_bytearr_to_type :: proc($T: typeid, dat: []u8) -> (ret: T, ok: bool) {
    if type_info_of(T).size != len(dat) {
        dbg.log(.ERROR, "Given byte arr does not have enough bytes to cast to T")
        return
    }

    return (cast(^T)(transmute(runtime.Raw_Slice)dat).data)^, true
}