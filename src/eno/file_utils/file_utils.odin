package file_utils

import dbg "../debug"

import "core:os"
import "core:testing"
import "core:strings"
import "core:log"
import "core:mem"
import "core:fmt"


FileReadError :: enum {
    None,
    FileReadError,
    PathDoesNotResolve,
}

read_lines_from_file :: proc(filepath: string) -> (lines: []string, err: FileReadError) {
    source: string; source, err = read_file_source(filepath)

    alloc_err: mem.Allocator_Error; lines, alloc_err = strings.split_lines(source)
    if alloc_err != mem.Allocator_Error.None {
        err = .FileReadError
        return
     }
    
    return lines, .None
}


read_lines_from_file_handle :: proc(file: os.Handle) -> (lines: []string, err: FileReadError) {
    source: string; source, err = read_source_from_handle(file)

    alloc_err: mem.Allocator_Error; lines, alloc_err = strings.split_lines(source)
    if alloc_err != mem.Allocator_Error.None {
        err = .FileReadError
        return
    }

    return lines, FileReadError.None
}

read_file_source :: proc(filepath: string) -> (source: string, err: FileReadError) {
    err = FileReadError.None

    file, os_path_err := os.open(filepath); defer os.close(file)
    if os_path_err != os.ERROR_NONE {
        err = FileReadError.PathDoesNotResolve
        return
    }

    return read_source_from_handle(file)
}

read_source_from_handle :: proc(file: os.Handle) -> (source: string, err: FileReadError) {
    err = FileReadError.None

    bytes, os_read_err := os.read_entire_file_from_handle_or_err(file);
    if os_read_err != os.ERROR_NONE {
        err = FileReadError.FileReadError
        return
    }

    source = string(bytes)
    return
}


@(test)
read_lines_test :: proc(t: ^testing.T) {
    lines, err := read_lines_from_file("resources/shaders/demo_shader.vert")
    defer delete(lines)

    testing.expect_value(t, FileReadError.None, err)

    log.infof("lines: %#s", lines)
}

@(test)
read_source_test :: proc(t: ^testing.T) {
    source, err := read_file_source("resources/shaders/demo_shader.frag")

    testing.expect_value(t, FileReadError.None, err)

    log.infof("source: %#s", source)
}


check_path :: proc(path: string, loc := #caller_location) -> (ok: bool) {
    ok = os.is_dir(path) || os.is_file(path)
    if !ok do dbg.debug_point(dbg.LogLevel.ERROR, "Path is not valid", loc)
    return
}

// Returns false if you give a folder path
file_path_to_folder_path :: proc(file_path: string) -> (folder_path: string, ok: bool) {
    length := len(file_path)
    if length == 0 ||  is_path_separator(file_path[length - 1]) do return

    next_seperator := length - 1
    for next_seperator >= 0 && !is_path_separator(file_path[next_seperator]){
        next_seperator -= 1
    }

    if next_seperator == -1 do return file_path, true
    return file_path[:next_seperator + 1], true
}

is_path_separator :: proc(to_check: byte) -> bool {
    return to_check == '/' || to_check == '\\';
}
