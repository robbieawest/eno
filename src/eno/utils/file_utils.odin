package utils

import "core:os"
import "core:testing"
import "core:strings"
import "core:log"
import "core:mem"

read_lines_from_file :: proc(filepath: string) -> (lines: []string, ok: bool) #optional_ok {
    f, err := os.open(filepath)
    if err != os.ERROR_NONE {
        log.errorf("%s: Could not open file specified: %s", #procedure, filepath)
        return nil, false
    }
    defer os.close(f)

    bytes, success := os.read_entire_file_from_filename(filepath)
    defer delete(bytes)

    if !success {
        log.errorf("%s: File %s could not be read into bytes", #procedure, filepath)
        return nil, false
    }

    builder: strings.Builder = strings.builder_make_len(len(bytes))
    defer strings.builder_destroy(&builder)

    written_bytes := strings.write_bytes(&builder, bytes)
    if written_bytes != len(bytes) {
        log.errorf("%s: Could not write all bytes from file to builder", #procedure)
        return nil, false
    }
    file_as_string: string = strings.to_string(builder)

    log.infof("file as string: \n%v", file_as_string)

    lines, err = strings.split_lines(file_as_string)
    if err != mem.Allocator_Error.None {
        log.errorf("%s: Allocator error when splitting file into lines", #procedure)
        return nil, false
    } 
    
    return lines, true
}

@(test)
read_lines_test :: proc(t: ^testing.T) {
    lines, ok := read_lines_from_file("resources/jsontest1.txt")
    testing.expect(t, ok, "ok check")
    defer delete(lines)

    log.infof("lines: %s", lines)
}
