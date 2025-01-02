package utils

import dbg "../debug"

import "core:os"
import "core:testing"
import "core:strings"
import "core:log"
import "core:mem"
import "core:fmt"

FileError :: union {
    mem.Allocator_Error,
    FileReadError
}

FileReadError :: enum {
    None,
    PathDoesNotResolve,
    FileReadError,
    PartialFileReadError,
}

read_lines_from_file :: proc(filepath: string) -> (lines: []string, err: FileError) {
    source: string; source, err = read_file_source(filepath)

    alloc_err: mem.Allocator_Error; lines, alloc_err = strings.split_lines(source)
    if alloc_err != mem.Allocator_Error.None {
        err = alloc_err
        return
     }
    
    return lines, FileReadError.None
}

read_file_source :: proc(filepath: string) -> (source: string, err: FileError) {
    err = FileReadError.None

    f, os_path_err := os.open(filepath); defer os.close(f)
    if os_path_err != os.ERROR_NONE {
        err = FileReadError.PathDoesNotResolve
        return
    }

    bytes, os_read_err := os.read_entire_file_from_handle_or_err(f); defer delete(bytes)
    if os_read_err != os.ERROR_NONE {
        err = FileReadError.FileReadError
        return
    }

    builder := strings.builder_make_len(len(bytes)); defer strings.builder_destroy(&builder)

    written_bytes := strings.write_bytes(&builder, bytes)
    if written_bytes != len(bytes) {
        err = FileReadError.PartialFileReadError
    }

    source = strings.to_string(builder)
    return
}


@(test)
read_lines_test :: proc(t: ^testing.T) {
    lines, err := read_lines_from_file("resources/jsontest1.txt")
    defer delete(lines)

    fileReadError, union_ok := err.(FileReadError)
    testing.expect(t, union_ok)
    testing.expect_value(t, FileReadError.None, fileReadError)

    log.infof("lines: %s", lines)
}
