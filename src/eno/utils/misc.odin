package utils

import dbg "../debug"

unwrap_maybe :: proc(maybe: Maybe($T), loc := #caller_location) -> (val: T, ok: bool) {
    val, ok = maybe.?; if !ok do dbg.log(dbg.LogLevel.ERROR, "Unwrapped nil maybe", loc=loc)
    return
}