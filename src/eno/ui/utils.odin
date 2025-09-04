package ui

import dbg "../debug"

import "core:mem"
import "core:strconv"

int_to_buf :: proc(#any_int num: int, #any_int lim: int, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    if num % 10 > lim {
        dbg.log(.ERROR, "Integer needs to many characters for ui buffer", loc=loc)
        return
    }
    byte_buf = make([]byte, lim, allocator)
    strconv.itoa(byte_buf, num)

    ok = true
    return
}

str_to_buf :: proc(str: string, #any_int lim: int, allocator: mem.Allocator, loc := #caller_location) -> (byte_buf: []byte, ok: bool) {
    dbg.log(.INFO, "Str to buf: %s, %d", str, lim)
    if len(str) > lim {
        dbg.log(.ERROR, "Environment texture uri is greater than the ui buffer char limit", loc=loc)
        return
    }

    byte_buf = make([]byte, lim, allocator)
    copy(byte_buf, transmute([]byte)str)

    ok = true
    return
}