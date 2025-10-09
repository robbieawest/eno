package ui

import dbg "../debug"

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"
import utils "../utils"

int_to_buf :: proc(#any_int num: int, #any_int lim: int, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    str := fmt.caprintf("%d", num, allocator=allocator)
    if len(str) > lim {
        dbg.log(.ERROR, "Integer needs to many characters for ui buffer: '%s'", str, loc=loc)
        return
    }

    return utils.to_bytes(str), true
}

float_to_buf :: proc(num: f32, #any_int lim: int, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    str := fmt.caprintf("%f", num, allocator=allocator)
    if len(str) > lim {
        dbg.log(.ERROR, "Float needs too many characters for ui buffer: '%s'", str, loc=loc)
        return
    }

    return utils.to_bytes(str), true
}

str_to_buf :: proc(str: string, #any_int lim: int, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    if len(str) > lim {
        dbg.log(.ERROR, "String needs too many characters for ui buffer: '%s'", str, loc=loc)
        return
    }

    return utils.to_bytes(strings.clone_to_cstring(str, allocator)), true
}