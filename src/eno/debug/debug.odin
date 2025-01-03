package debug

import gl "vendor:OpenGL"

import "core:log"
import "core:strings"
import "core:fmt"
import "core:mem"
import "base:runtime"

// ToDo Write options for debugging

DEBUG_STACK: ^DebugStack = nil
init_debug_stack :: proc() {
    DEBUG_STACK = new(DebugStack)
}

DEBUG_PANIC_ON_ERROR := false

GL_DEBUG_CALLBACK :: proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr) {
    context = runtime.default_context()
    context.logger = log.create_console_logger()


    builder, err := strings.builder_make()
    defer strings.builder_destroy(&builder)
    if err != mem.Allocator_Error.None do log.errorf("Could not allocate debug stack builder")

    fmt.sbprintfln(&builder, "\n************* OpenGL Log **************\nMessage: %s", strings.clone_from_cstring(message))
    
    debug_stack_out_depth := DEBUG_PANIC_ON_ERROR ? DEBUG_STACK.curr_items : 3


    if DEBUG_STACK == nil {
        log.warn("Debug stack has not been initialized, no head to return")
    }
    else {
        fmt.sbprint(&builder,
        "\n\n**** Returning head of debug stack : head size = ",
        uint(debug_stack_out_depth),
        " ****\n\n"
        )

        debug_stack_head: ^StackItem = DEBUG_STACK.stack_head
        debug_info: ^DebugInfo = nil

        i: u32
        for i = 0; i < debug_stack_out_depth && debug_stack_head != nil; i += 1 {
            debug_info, debug_stack_head = read_last_debug_point(debug_stack_head)
            fmt.sbprintfln(&builder,
            "Debug point >> %s '%s' %s:%s:%d:%d",
            log_level_to_string(debug_info.log_info.level),
            debug_info.log_info.msg,
            parse_debug_source_path(debug_info.loc.file_path),
            debug_info.loc.procedure,
            int(debug_info.loc.line),
            int(debug_info.loc.column),
            )
        }
        if i < debug_stack_out_depth do fmt.sbprint(&builder, "Stack smaller than head size\n")
    }

    switch (severity) {
    case gl.DEBUG_SEVERITY_MEDIUM, gl.DEBUG_SEVERITY_HIGH:
        log.errorf("%s", strings.to_string(builder))
    case:
        log.warnf("%s", strings.to_string(builder))
    }
}

@(private)
parse_debug_source_path :: proc(source_path: string) -> (ret: string) {
    start_of_relative_path := strings.index(source_path, "eno/src/eno") // Assumes this path does not come up before
    return source_path[start_of_relative_path+11:]
}


LogLevel :: enum { INFO, WARN, ERROR }
LogInfo :: struct {
    msg: string,
    level: LogLevel
}

log_level_to_string :: proc(level: LogLevel) -> string {
    switch (level) {
    case .INFO: return "INFO"
    case .WARN: return "WARN"
    case .ERROR: return "ERROR"
    }
    return "why"
}

DebugInfo :: struct {
    loc: runtime.Source_Code_Location,
    log_info: LogInfo
}


StackItem :: struct {
    prev: ^StackItem,
    next: ^StackItem,
    data: DebugInfo
}


MAX_DEBUG_STACK :: 128
DebugStack :: struct {
    curr_items: u32,
    stack_tail: ^StackItem,
    stack_head: ^StackItem
}


debug_point :: proc { debug_point_no_log, debug_point_log }

@(private)
debug_point_no_log :: proc(loc := #caller_location) {
    debug_info: DebugInfo
    debug_info.loc = loc
    push_to_debug_stack(DEBUG_STACK, debug_info)
}

@(private)
debug_point_log :: proc(log_info: LogInfo, loc := #caller_location) {
    push_to_debug_stack(DEBUG_STACK, DebugInfo{ loc, log_info })

    switch log_info.level {
    case .INFO:
        log.info(log_info.msg, location = loc)
    case .WARN:
        log.warn(log_info.msg, location = loc)
    case .ERROR:
        log.error(log_info.msg, location = loc)
    }
}


@(private)
push_to_debug_stack :: proc(stack: ^DebugStack, debug_info: DebugInfo) {
    if (stack == nil) {
        log.warn("Debug stack not initialized", location = debug_info.loc)
        return
    }

    if (stack.curr_items == MAX_DEBUG_STACK) {
        // Remove off of tail
        temp_stack_tail := stack.stack_tail
        stack.stack_tail = stack.stack_tail.next
        stack.curr_items -= 1
    }

    new_stack_item: ^StackItem = new(StackItem)
    new_stack_item.prev = stack.stack_head
    new_stack_item.data = debug_info

    if stack.stack_tail == nil do stack.stack_tail = new_stack_item
    else if stack.stack_head != nil {
        stack.stack_head.next = new_stack_item
    }

    stack.stack_head = new_stack_item
    stack.curr_items += 1
}


// Doesn't technically pop, just deletes from the head
@(private)
pop_from_debug_stack :: proc(stack: ^DebugStack) {
    if (stack.stack_head == nil) do return

    temp_stack_head := stack.stack_head
    stack.stack_head = stack.stack_head.prev
    stack.curr_items -= 1
}

@(private)
read_last_debug_point :: proc { read_top_debug_stack, read_top_debug_stack_item }

@(private)
read_top_debug_stack :: proc(stack: ^DebugStack) -> (debug_info: ^DebugInfo, debug_short_stack: ^StackItem) { // Nullable
    if (stack.stack_head == nil) do return nil, nil
    return &stack.stack_head.data, stack.stack_head.prev
}

@(private)
read_top_debug_stack_item :: proc(stack_item: ^StackItem) -> (debug_info: ^DebugInfo, debug_short_stack: ^StackItem) { // Nullable
    if (stack_item == nil) do return nil, nil
    return &stack_item.data, stack_item.prev
}

destroy_debug_stack :: proc() {
    free(DEBUG_STACK)
}