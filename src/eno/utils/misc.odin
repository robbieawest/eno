package utils

import dbg "../debug"

unwrap_maybe_ptr :: proc(maybe: ^Maybe($T), loc := #caller_location) -> (val: ^T, ok: bool) {
    if maybe == nil {
        dbg.log(dbg.LogLevel.ERROR, "Given maybe is invalid (nil)", loc=loc)
        return
    }
    return &maybe.?, true
}

unwrap_maybe:: proc(maybe: Maybe($T), loc := #caller_location) -> (val: T, ok: bool) {
    if maybe == nil {
        dbg.log(dbg.LogLevel.ERROR, "Given maybe is invalid (nil)", loc=loc)
        return
    }

    return maybe.?, true
}
