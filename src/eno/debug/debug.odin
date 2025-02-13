package debug

import gl "vendor:OpenGL"

import "core:log"
import "core:strings"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:slice"

import "base:runtime"


DebugMode :: enum {
    RELEASE, DEBUG
}
DEBUG_MODE: DebugMode = .DEBUG

// Creates debug stack if nil
ENABLE_DEBUG :: proc() {
    DEBUG_MODE = .DEBUG
    debug_point_log = d_Debug_point_log
    debug_point_no_log = d_Debug_point_no_log

    gl.Enable(gl.DEBUG_OUTPUT)
    gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
}

// Clears debug stack
ENABLE_RELEASE :: proc() {
    DEBUG_MODE = .RELEASE
    debug_point_log = r_Debug_point_log
    debug_point_no_log = r_Debug_point_no_log

    gl.Disable(gl.DEBUG_OUTPUT)
    gl.Disable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
    destroy_debug_stack()
}


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
    DISPLAY_DEBUG_STACK = true, DEBUG_STACK_HEAD_SIZE = 6, DISPLAY_DEBUG_STACK_SMALLER_THAN_HEAD_SIZE = true,
    PUSH_LOGS_TO_DEBUG_STACK = true, PUSH_INFOS_TO_DEBUG_STACK = true, PUSH_WARNINGS_TO_DEBUG_STACK = true,
    PUSH_ERRORS_TO_DEBUG_STACK = true, PUSH_GL_LOG_TO_DEBUG_STACK = true
}



GL_DEBUG_CALLBACK :: proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr) {
    context = runtime.default_context()
    context.logger = log.create_console_logger()


    builder, err := strings.builder_make()
    if err != mem.Allocator_Error.None do log.errorf("Could not allocate debug stack builder")

    s_Message: string = strings.clone_from_cstring(message)
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
            level, ok := reflect.enum_name_from_value(debug_info.log_info.level); if !ok do return
            fmt.sbprintfln(&builder,
                "Debug point >> %s '%s' %s:%s:%d:%d",

                level,
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

        if DEBUG_FLAGS.PUSH_GL_LOG_TO_DEBUG_STACK do push_to_debug_stack({ fmt.aprintf("OpenGL LogL %s", s_Message), .ERROR})
    case:
        log.warnf("%s", strings.to_string(builder))

        if DEBUG_FLAGS.PUSH_GL_LOG_TO_DEBUG_STACK do push_to_debug_stack({ fmt.aprintf("OpenGL LogL %s", s_Message), .WARN})
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

/*
// Debug info assumes LogInfo
destroy_debug_info :: proc(debug_info: ^DebugInfo) {

}
*/


StackItem :: struct {
    prev: ^StackItem,
    next: ^StackItem,
    data: DebugInfo
}

destroy_stack_item :: proc(stack_item: ^StackItem) {
    if len(stack_item.data.log_info.msg) != 0 && stack_item.data.log_info.msg != DEBUG_MARKER do delete(stack_item.data.log_info.msg)
    free(stack_item)
}

// Used inside of destroy stack call, destroys recursively
@(private)
r_Destroy_stack_item :: proc(stack_item: ^StackItem) {
    if stack_item == nil do return
    destroy_stack_item(stack_item)
    r_Destroy_stack_item(stack_item.prev)
}


MAX_DEBUG_STACK :: 16
DebugStack :: struct {
    curr_items: u32,
    stack_tail: ^StackItem,
    stack_head: ^StackItem
}

// Debug stack is very literally a stack with FIFO (first in first out).
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
        if stack.stack_tail == nil || stack.stack_tail.next == nil {
            log.error("Debug stack is invalid")
            return
        }
        temp_stack_tail := stack.stack_tail
        stack.stack_tail = stack.stack_tail.next
        stack.stack_tail.prev = nil
        stack.curr_items -= 1

        destroy_stack_item(temp_stack_tail)
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
    if DEBUG_STACK == nil do return

    r_Destroy_stack_item(DEBUG_STACK.stack_head)
    free(DEBUG_STACK)
    DEBUG_STACK = nil
}


debug_point :: proc { debug_point_no_log, debug_point_log }

@(private)
p_Debug_point_no_log :: #type proc(debug_flags := DEBUG_FLAGS, loc := #caller_location)
debug_point_no_log: p_Debug_point_no_log = DEBUG_MODE == .RELEASE ? r_Debug_point_no_log : d_Debug_point_no_log

r_Debug_point_no_log :: proc(debug_flags := DEBUG_FLAGS, loc := #caller_location) {
    // Do nothing
}

DEBUG_MARKER := " ** Debug Marker ** "
d_Debug_point_no_log :: proc(debug_flags := DEBUG_FLAGS, loc := #caller_location) {
    if debug_flags.PUSH_LOGS_TO_DEBUG_STACK do push_to_debug_stack({ DEBUG_MARKER, .INFO }, loc = loc)
}


@(private)
p_Debug_point_log :: #type proc(level: LogLevel, fmt_msg: string, fmt_args: ..any, debug_flags := DEBUG_FLAGS, loc := #caller_location)
debug_point_log: p_Debug_point_log = DEBUG_MODE == .RELEASE ? r_Debug_point_log : d_Debug_point_log

r_Debug_point_log :: proc(level: LogLevel, fmt_msg: string, fmt_args: ..any, debug_flags := DEBUG_FLAGS, loc := #caller_location) {
    // Do nothing
}

d_Debug_point_log :: proc(level: LogLevel, fmt_msg: string, fmt_args: ..any, debug_flags := DEBUG_FLAGS, loc := #caller_location) {
    format_needed := len(fmt_args) == 0
    out_msg := format_needed ? strings.clone(fmt_msg) : fmt.aprintf(fmt_msg, ..fmt_args)  // clone prevents bad free
    defer if DEBUG_STACK == nil do delete(out_msg)

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


PrintDebugStackFlag :: enum {
    OUT_EVERYTHING,
    LOG_INFO_ONLY,
    OUT_INFO,
    OUT_WARN,
    OUT_ERROR
}; PrintDebugStackFlags :: bit_set[PrintDebugStackFlag]
DEFAULT_PRINT_DEBUG_STACK_FLAGS := PrintDebugStackFlags{ .LOG_INFO_ONLY, .OUT_INFO, .OUT_WARN, .OUT_ERROR }

log_debug_stack :: proc(flags := DEFAULT_PRINT_DEBUG_STACK_FLAGS, debug_stack := DEBUG_STACK) {
    debug_stack_out := aprint_debug_stack(flags, debug_stack); defer delete(debug_stack_out)
    log.infof("Debug stack: \n%#v", debug_stack_out)
}

print_debug_stack :: proc(flags := DEFAULT_PRINT_DEBUG_STACK_FLAGS, debug_stack := DEBUG_STACK) {
    debug_stack_out := aprint_debug_stack(flags, debug_stack); defer delete(debug_stack_out)
    fmt.printf("Debug stack: %#v", debug_stack_out)
}

aprint_debug_stack :: proc(flags := DEFAULT_PRINT_DEBUG_STACK_FLAGS, debug_stack := DEBUG_STACK) -> (ret: string) {
    builder := strings.builder_make()

    sbprint_stack_item(debug_stack.stack_head, &builder, flags)

    ret = strings.to_string(builder)
    return
}

sbprint_stack_item :: proc(stack_item: ^StackItem, builder: ^strings.Builder, flags := DEFAULT_PRINT_DEBUG_STACK_FLAGS) {
    if stack_item == nil {
        strings.write_string(builder, "End of debug stack")
        return
    }

    if .OUT_EVERYTHING in flags {
        fmt.sbprintf(builder, "%#v\n", stack_item)
    }
    else if .LOG_INFO_ONLY in flags {
        debug_info := stack_item.data
        switch debug_info.log_info.level {
        case .INFO: if .OUT_INFO in flags do fmt.sbprintf(builder, "[%v] : %v : %v\n", debug_info.log_info.level, debug_info.loc, debug_info.log_info.msg)
        case .WARN: if .OUT_WARN in flags do fmt.sbprintf(builder, "[%v] : %v : %v\n", debug_info.log_info.level, debug_info.loc, debug_info.log_info.msg)
        case .ERROR: if .OUT_ERROR in flags do fmt.sbprintf(builder, "[%v] : %v : %v\n", debug_info.log_info.level, debug_info.loc, debug_info.log_info.msg)
        }
    }

    sbprint_stack_item(stack_item.prev, builder, flags)
}
