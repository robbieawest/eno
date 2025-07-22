package queue_utils

import dbg "../../debug"

import "core:container/queue"
import "core:mem"

QueueError :: enum {
    None,
    No_Space,
    Not_Enough_Elems,
    Allocator_Err,
    Unknown
}

/*
    Does not return popped elems
*/
remove_back_n_elems :: proc(queue_in: ^$Q/queue.Queue($T), n: int) -> (err: QueueError) {

    pop_ok: bool
    for i := 0; i < n; i += 1 {
        _, pop_ok = queue.pop_back_safe(queue_in); if !pop_ok {
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

/*
    Should not grow queue, returns an error when size of elems is greater than the queue space
*/
push_front_elems :: proc(queue_in: ^$Q/queue.Queue($T), elems: ..T) -> (err: QueueError) {
    if len(elems) > queue.space(queue_in^) {
        err = .No_Space
        return
    }

    push_ok: bool; alloc_err: mem.Allocator_Error
    for elem in elems {
        push_ok, alloc_err = queue.push_front(queue_in, elem)
        if !push_ok {
            err = .Unknown
            return
        }
        if alloc_err != .None {
            err = .Allocator_Err
            return
        }
    }

    err = .None
    return
}


handle_queue_error :: proc(err: QueueError, loc := #caller_location) {
    switch err {
    case .No_Space: dbg.log(.ERROR, "Error while manipulating queue: No space to perform operation", loc = loc)
    case .Not_Enough_Elems: dbg.log(.ERROR, "Error while manipulating queue: Not enough elements to perform operation", loc = loc)
    case .Allocator_Err: dbg.log(.ERROR, "Error while manipulating queue: Allocator error")
    case .Unknown: dbg.log(.ERROR, "Breaking error while attempting to manipulate queue")
    case .None:
    }
}