package model

import "core:log"
import "core:os"
import "core:strings"

// This class defines data transfer
// Currently implemented for parsing and representing JSON input

JSONInner :: union {
    ^JSONResult,
    any
}

JSONResult :: struct { //Size will not be known at runtime apparently
    key: string,
    value: JSONInner
}

@(private)
read_lines_from_file :: proc(filepath: string) -> (lines: []string, ok: bool) #optional_ok {
    ok = true

    f, err := os.open(filepath)
    if err != os.ERROR_NONE {
        log.errorf("%s: Could not open file specified: %s", #procedure, filepath)
        return nil, false
    }
    defer os.close(f)

    bytes, success = os.read_entire_file_from_filename(filepath)
    if !success {
        log.errorf("%s: File %s could not be read into bytes", #procedure, filepath)
        return nil, false
    }

    file_as_string: string = strings.to_string(strings.builder_from_bytes(bytes))

    lines = strings.split(file_as_string, "\n")
    if lines == nil do ok = false
    
    return lines, ok
}

parse_json_from_file :: proc(filepath: string) -> (res: ^JSONResult, ok: bool) #optional_ok {

    lines: []string = read_lines_from_file(filepath)
    if lines == nil {
        log.errorf("%s: Could not read lines from file: %s", #procedure, filepath)
        return nil, false
    }
    
    //Identify lines containing key value assignment with ':'
    //ToDo: Implement

    result = new(JSONResult)

    return result, true
}

destroy_json_result :: proc(result: ^JSONResult) {
    destroy_json_inner(result.value)
    free(result)
}

@(private)
destroy_json_inner :: proc(inner: ^JSONInner) {
    json_res, ok := inner.(^JSONResult)
    if ok do destroy_json_result(json_res)
    else {
        any_res, ok := inner.(any)
        if !ok do log.errorf("Type error should not happen in %s", #procedure)
        free(any_res.data)
        delete(any_res)
    }
}
