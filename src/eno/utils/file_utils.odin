package utils

import dbg "../debug"

import "core:os"
import "core:testing"
import "core:strings"
import "core:log"
import "core:mem"
import "core:fmt"


read_lines_from_file :: proc(filepath: string) -> (lines: []string, ok: bool) #optional_ok {
    source := read_file_source(filepath) or_return

    err: mem.Allocator_Error; lines, err = strings.split_lines(source)
    if err != mem.Allocator_Error.None {
        log.errorf("%s: Allocator error when splitting file into lines", #procedure)
        return nil, false
    } 
    
    return lines, true
}

read_file_source :: proc(filepath: string) -> (source: string, ok: bool) {
    f, err := os.open(filepath)
    if err != os.ERROR_NONE {
        log.errorf("%s: Could not open file specified: %s", #procedure, filepath)
        return
    }
    defer os.close(f)

    bytes, success := os.read_entire_file_from_filename(filepath)
    defer delete(bytes)

    if !success {
        dbg.debug_point(dbg.LogInfo{ msg = fmt.aprintf("%s: File %s could not be read into bytes", #procedure, filepath), level = .ERROR })
        return
    }

    builder: strings.Builder = strings.builder_make_len(len(bytes))
    defer strings.builder_destroy(&builder)

    written_bytes := strings.write_bytes(&builder, bytes)
    if written_bytes != len(bytes) {
        log.errorf("%s: Could not write all bytes from file to builder", #procedure)
        return
    }

    ok = true
    source = strings.to_string(builder)
    return
}


@(test)
read_lines_test :: proc(t: ^testing.T) {
    lines, ok := read_lines_from_file("resources/jsontest1.txt")
    testing.expect(t, ok, "ok check")
    defer delete(lines)

    log.infof("lines: %s", lines)
}
