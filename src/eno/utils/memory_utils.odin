package utils

import dbg "../debug"

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