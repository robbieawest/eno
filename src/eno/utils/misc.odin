package utils

import dbg "../debug"

// Miscellaneos utils

/* Unwrappes the given maybe with an ok check, outputs debug information.
Ok is returned back, therefore it is safe just to call or_return on call.
*/
unwrap_maybe :: proc(maybe: Maybe($T)) -> (val: T, ok: bool) {
    val, ok = maybe.?; if !ok do dbg.debug_point(dbg.LogLevel.ERROR)
    return
}