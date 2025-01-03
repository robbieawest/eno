package debug

import gl "vendor:OpenGL"

import "../utils"

import "core:log"
import "core:strings"
import "core:fmt"
import "core:mem"
import "core:reflect"

import "base:runtime"


// Options for debugging
DebugFlags :: bit_field u32 {  // Extend if needed
    DISPLAY_INFO: bool                                  | 1,
    DISPLAY_WARNING: bool                               | 1,
    DISPLAY_ERROR: bool                                 | 1,
    DISPLAY_DEBUG_STACK: bool                           | 1,
    DISPLAY_DEBUG_STACK_UNINITIALIZED: bool             | 1,
    DISPLAY_DEBUG_STACK_SMALLER_THAN_HEAD_SIZE: bool    | 1,
    PUSH_ERRORS_TO_DEBUG_STACK: bool                    | 1,
    PUSH_WARNINGS_TO_DEBUG_STACK: bool                  | 1,
    PUSH_INFOS_TO_DEBUG_STACK: bool                     | 1,
    PUSH_LOGS_TO_DEBUG_STACK: bool                      | 1,
    PUSH_GL_LOG_TO_DEBUG_STACK: bool                    | 1,
    PANIC_ON_ERROR: bool                                | 1,
    PANIC_ON_GL_ERROR: bool                             | 1,
    DEBUG_STACK_HEAD_SIZE: u8                           | 8
}

// Used in debug calls where specified as an optional parameter, can be overwritten
// DEBUG_FLAGS.PANIC_ON_ERROR = true
// ^ This enables error panicking
DEBUG_FLAGS := DebugFlags{
    DISPLAY_INFO = true, DISPLAY_WARNING = true, DISPLAY_ERROR = true, DISPLAY_DEBUG_STACK_UNINITIALIZED = true,
    DISPLAY_DEBUG_STACK = true, DEBUG_STACK_HEAD_SIZE = 3, DISPLAY_DEBUG_STACK_SMALLER_THAN_HEAD_SIZE = true
}



GL_DEBUG_CALLBACK :: proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr) {
    context = runtime.default_context()
    context.logger = log.create_console_logger()


    builder, err := strings.builder_make()
    if err != mem.Allocator_Error.None do log.errorf("Could not allocate debug stack builder")

    s_Message := strings.clone_from_cstring(message)
    fmt.sbprintfln(&builder, "\n************* OpenGL Log **************\nMessage: %s", s_Message)

    if DEBUG_FLAGS.DISPLAY_DEBUG_STACK_UNINITIALIZED &&  DEBUG_STACK == nil {
        log.warn("Debug stack has not been initialized, no head to return")
    }
    else {
        fmt.sbprintf(&builder,
            "\n\n**** Returning head of debug stack : head size = %i %s",
            DEBUG_FLAGS.DEBUG_STACK_HEAD_SIZE,
            " ****\n\n"
        )

        debug_stack_head: ^StackItem = DEBUG_STACK.stack_head
        debug_info: ^DebugInfo = nil

        i: u8
        for i = 0; i < DEBUG_FLAGS.DEBUG_STACK_HEAD_SIZE && debug_stack_head != nil; i += 1 {
            debug_info, debug_stack_head = read_last_debug_point(debug_stack_head)
            fmt.sbprintfln(&builder,
                "Debug point >> %s '%s' %s:%s:%d:%d",

                reflect.enum_name_from_value(debug_info.log_info.level),
                debug_info.log_info.msg,
                parse_debug_source_path(debug_info.loc.file_path),
                debug_info.loc.procedure,
                int(debug_info.loc.line),
                int(debug_info.loc.column),
            )
        }
        if DEBUG_FLAGS.DISPLAY_DEBUG_STACK_SMALLER_THAN_HEAD_SIZE && i < DEBUG_FLAGS.DEBUG_STACK_HEAD_SIZE do strings.write_string(&builder, "Stack smaller than head size\n")
    }


    switch (severity) {
    case gl.DEBUG_SEVERITY_MEDIUM, gl.DEBUG_SEVERITY_HIGH:
        log.errorf("%s", strings.to_string(builder))

        if severity == gl.DEBUG_SEVERITY_HIGH {
            if DEBUG_FLAGS.PANIC_ON_ERROR do panic("Panic raised on OpenGL error via DebugFlags.PANIC_ON_ERROR")
            else if DEBUG_FLAGS.PANIC_ON_GL_ERROR do panic("Panic raised on OpenGL error via DebugFlags.PANIC_ON_GL_ERROR")
        }

        if DEBUG_FLAGS.PUSH_GL_LOG_TO_DEBUG_STACK do push_to_debug_stack({ utils.concat("OpenGL LogL ", s_Message), .ERROR})
    case:
        log.warnf("%s", strings.to_string(builder))

        if DEBUG_FLAGS.PUSH_GL_LOG_TO_DEBUG_STACK do push_to_debug_stack({ utils.concat("OpenGL LogL ", s_Message), .WARN})
    }


}


@(private)
parse_debug_source_path :: proc(source_path: string) -> (ret: string) {
    debug_path_limiter := "eno/src/eno"
    start_of_relative_path := strings.index(source_path, debug_path_limiter) // Assumes this path does not come up before
    return source_path[start_of_relative_path + len(debug_path_limiter):]
}


LogLevel :: enum { INFO, WARN, ERROR }
LogInfo :: struct {
    msg: string,
    level: LogLevel
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

// Debug stack is very literally a stack
DEBUG_STACK: ^DebugStack = nil
init_debug_stack :: proc() {
    DEBUG_STACK = new(DebugStack)
}


@(private)
push_to_debug_stack :: proc(log_info: LogInfo, stack := DEBUG_STACK, loc := #caller_location) {
    debug_info := DebugInfo{ loc, log_info }
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


debug_point :: proc { debug_point_no_log, debug_point_log }

@(private)
debug_point_no_log :: proc(debug_flags := DEBUG_FLAGS, loc := #caller_location) {
    if debug_flags.PUSH_LOGS_TO_DEBUG_STACK do push_to_debug_stack({ " ** Debug Marker ** ", .INFO}, loc = loc)
}

@(private)
debug_point_log :: proc(level: LogLevel, fmt_msg: string, fmt_args: ..any, debug_flags := DEBUG_FLAGS, loc := #caller_location) {
    out_msg := len(fmt_args) == 0 ? fmt_msg : fmt.aprintf(fmt_msg, fmt_args)

    switch level {
    case .INFO:
        if debug_flags.DISPLAY_INFO do log.info(out_msg, location = loc)
        if debug_flags.PUSH_INFOS_TO_DEBUG_STACK do push_to_debug_stack({ out_msg, level }, loc = loc)
    case .WARN:
        if debug_flags.DISPLAY_WARNING do log.warn(out_msg, location = loc)
        if debug_flags.PUSH_WARNINGS_TO_DEBUG_STACK do push_to_debug_stack({ out_msg, level }, loc = loc)
    case .ERROR:
        if debug_flags.DISPLAY_ERROR do log.error(out_msg, location = loc)
        if debug_flags.PUSH_ERRORS_TO_DEBUG_STACK do push_to_debug_stack({ out_msg, level }, loc = loc)
    }
}