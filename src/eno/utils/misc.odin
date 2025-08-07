package utils

import dbg "../debug"

unwrap_maybe_ptr :: proc(maybe: Maybe($T), loc := #caller_location) -> (val: ^T, ok: bool) {
    val, ok = &maybe.?; if !ok do dbg.log(dbg.LogLevel.ERROR, "Given maybe is invalid (nil)", loc=loc)
    return
}

unwrap_maybe:: proc(maybe: Maybe($T), loc := #caller_location) -> (val: T, ok: bool) {
    val = (unwrap_maybe_ptr(maybe, loc) or_return)^
    ok = true
    return
}
