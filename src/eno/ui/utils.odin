package ui

import dbg "../debug"

import "core:fmt"
import "core:mem"
import "core:strings"

import "base:runtime"

MAX_LIM : int = 0x0F0

buf_from_fmt :: proc(#any_int lim: int, allocator: mem.Allocator, fmt_str: string, fmt_args: ..any, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    if lim < 0 || lim > MAX_LIM {
        dbg.log(.ERROR, "Buffer limit is invalid", loc=loc)
        return
    }
    builder, err := strings.builder_make_len_cap(0, lim + 1, allocator); if err != .None {  // Is null terminated via lim + 1
        dbg.log(.ERROR, "Builder alloc error", loc=loc)
        return
    }

    str_res := fmt.sbprintf(&builder, fmt_str, ..fmt_args)
    if len(str_res) > lim {
        strings.builder_destroy(&builder)
        dbg.log(.ERROR, "Formatted string does not fit in buffer with limit", loc=loc)
        return
    }

    byte_buf = transmute([]byte)runtime.Raw_Slice{ raw_data(builder.buf), lim + 1}
    ok = true
    return
}

int_to_buf :: proc(#any_int num: int, #any_int lim: uint, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    return buf_from_fmt(lim, allocator, "%i", num, loc=loc)
}

float_to_buf :: proc(num: f32, #any_int lim: uint, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    return buf_from_fmt(lim, allocator, "%f", num, loc=loc)

}

str_to_buf :: proc(str: string, #any_int lim: int, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    return buf_from_fmt(lim, allocator, "%s", str, loc=loc)
}