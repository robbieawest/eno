package eno

import "core:mem"
import "base:runtime"

alloc_dynamic :: proc(type: typeid, allocator := context.allocator) -> (any, runtime.Allocator_Error) {
    info := type_info_of(type)
    ptr, alloc_err := mem.alloc(info.size, info.align, allocator)
    return any { ptr, type }, alloc_err
}
