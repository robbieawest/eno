package model

import "core:log"
import "core:os"
import "core:strings"

// This class defines data transfer
// Currently implemented for parsing and representing JSON input

JSONInner :: union {
    ^JSONResult,
    any //any because easy. Any is a really simple concept, you just have to handle a rawptr.
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

parse_json_from_file :: proc(filepath: string) -> (res: []^JSONResult, ok: bool) #optional_ok {

    lines: []string = read_lines_from_file(filepath)
    if lines == nil {
        log.errorf("%s: Could not read lines from file: %s", #procedure, filepath)
        return nil, false
    }
    

    // Identify lines containing key value assignment with ':' and split them

    // Root describes the root of the current line to be parsed
    // If the root is the full root of the input JSON then `root` is nil, else the root points to the JSONResult, so the line can insert itself as a JSONInner
    root: ^JSONResult = nil 

    JSONOut := [dynamic]JSONResult

    for line, i in lines {
        containsAssignment, inQuotes, bracketOpens, bracketCloses := false
        nEndCommas := 0

        for char, j in line { //Runes loop
            #partial switch char {
                case '\"' :inQuotes = !inQuotes
                case ':': if !inQuotes do containsAssignment = true
                case '{': bracketOpens = true
                case '}': bracketCloses = true
                case ',': if !inQuotes do nEndCommands += 1
            }
        }

        if bracketOpens {
            if bracketCloses {
                // JSONInner described in the same line
                // Split statements by commas
            }
            else {
                // JSONInner described over the next few lines
            }

        }
        else {
            if (nEndCommas == 0) {
                log.errorf("%s: JSON parsing error: No commas to designate line end", #procedure)
                return nil, false
            }
            else if (nEndCommas > 1) {
                log.errorf("%s: JSON parsing error: Multiple commas designating line end", #procedure)
                return nil, false
            }
            
            // End of recursion, given a direct value (no more JSONInner)
            splitByAssignment: []string = strings.split(line, ':') //change to a new implementation of split_last
            

        }


    }

}

@(private)
parse_key :: proc(key_line: string, call_proc: string) -> (key: string, ok: bool) {
    key_builder := strings.builder_make()
    nQuotes := 0

    for char, i in key_line {
        if char == '\"' {
            if nQuotes <= 1 do inQuotes += 1
            else {
                log.errorf("%s: JSON parsing error: Number of quotes in key is irregular", call_proc)
                return "", false
            }
        }
        else if inQuotes != 1 {
            // If not inside the quotes
            log.errorf("%s: JSON parsing error: Irregular character when parsing key at index: %d", call_proc, i)
            return "", false
        }
        else do strings.write_rune(&key_builder, char)
    }

    return strings.to_string(key_builder)
}


destroy_json :: proc {destroy_json_result, destroy_json_results }

@(private)
destroy_json_result :: proc(results: []^JSONResult) {
    for result in results do destroy_json_result(result)
}

@(private)
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
