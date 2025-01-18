package queue_utils

import dbg "../../debug"

import "core:container/queue"

QueueError :: enum {
    None,
    No_Space,
    Not_Enough_Elems
}

/*
    Does not return popped elems
*/
remove_back_n_elems :: proc(queue_in: ^$Q/queue.Queue($T), n: int) -> (err: QueueError) {

    pop_ok: bool
    for i := 0; i < n; i += 1 {
        _, pop_ok = queue.pop_back_safe(&queue_in); if !pop_ok {
            err = .Not_Enough_Elems
            return
        }
    }

    return
}

pop_back_n_elems :: proc(queue_in: ^$Q/queue.Queue($T), n: int) -> (elems: []T, err: QueueError) {
    elems = make([]T, n)

    pop_ok: bool
    for i := 0; i < n; i += 1 {
        elems[i], pop_ok = queue.pop_back_safe(&queue_in); if !pop_ok {
            err = .Not_Enough_Elems
            return
        }
    }

    return
}


handle_queue_error :: proc(err: QueueError, loc := #caller_location) {
    switch err {
    case .No_Space: dbg.debug_point(dbg.LogLevel.ERROR, "Error while manipulating queue: No space to perform operation", loc = loc)
    case .Not_Enough_Elems: dbg.debug_point(dbg.LogLevel.ERROR, "Error while manipulating queue: Not enough elements to perform operation", loc = loc)
    case .None:
    }
}