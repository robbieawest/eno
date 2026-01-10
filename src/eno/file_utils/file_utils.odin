package file_utils

import dbg "../debug"

import "core:os"
import "core:testing"
import "core:strings"
import "core:log"
import "core:mem"


FileReadError :: enum {
    None,
    FileReadError,
    PathDoesNotResolve,
}

read_lines_from_file :: proc(filepath: string, allocator := context.allocator) -> (lines: []string, err: FileReadError) {
    source: string; source, err = read_file_source(filepath, allocator)

    alloc_err: mem.Allocator_Error; lines, alloc_err = strings.split_lines(source, allocator)
    if alloc_err != mem.Allocator_Error.None {
        err = .FileReadError
        return
     }
    
    return lines, .None
}


read_lines_from_file_handle :: proc(file: os.Handle, allocator := context.allocator) -> (lines: []string, err: FileReadError) {
    source: string; source, err = read_source_from_handle(file, allocator)

    alloc_err: mem.Allocator_Error; lines, alloc_err = strings.split_lines(source, allocator)
    if alloc_err != mem.Allocator_Error.None {
        err = .FileReadError
        return
    }

    return lines, FileReadError.None
}

read_file_source :: proc(filepath: string, allocator := context.allocator) -> (source: string, err: FileReadError) {
    err = FileReadError.None

    file, os_path_err := os.open(filepath); defer os.close(file)
    if os_path_err != os.ERROR_NONE {
        err = FileReadError.PathDoesNotResolve
        return
    }

    return read_source_from_handle(file, allocator=allocator)
}

read_source_from_handle :: proc(file: os.Handle, allocator := context.allocator) -> (source: string, err: FileReadError) {
    err = FileReadError.None

    bytes, os_read_err := os.read_entire_file_from_handle_or_err(file, allocator);
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
    if !ok do dbg.log(.ERROR, "Path is not valid: %s", path, loc=loc)
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


get_directory_contents :: proc(cwd: string, num_files := 0, allocator := context.allocator) -> (contents: []os.File_Info, ok: bool) {
    dir_handle, ferr := os.open(cwd)
    defer os.close(dir_handle)
    if ferr != nil {
        dbg.log(.ERROR, "Error opening directory %s, error: %v", cwd, ferr)
        return
    }

    // Defaults to reading 100 files when num_files = 0
    contents, ferr = os.read_dir(dir_handle, num_files)
    if ferr != nil {
        dbg.log(.ERROR, "Error reading directory %s, error: %v", cwd, ferr)
        return
    }

    ok = true
    return
}

split_extension_from_path :: proc(path: string, allocator := context.allocator) -> (base_path: string, ext: string, ok: bool) {
    if len(path) == 0 || os.is_path_separator(rune(path[len(path) - 1])) {
        return
    }

    split := strings.split_n(path, ".", 2, allocator)
    if len(split) != 2 {
        ok = true
        return
    }

    return split[0], split[1], true
}
