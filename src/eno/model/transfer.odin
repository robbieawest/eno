package model

import "core:log"
import "core:os"
import "core:strings"
import "core:unicode"
import "core:strconv"

// This class defines data transfer
// Currently implemented for parsing and representing JSON input
// *none of this is tested yet

AcceptedValues :: enum { STRING, BOOL, INT, FLOAT }
JSONValue :: union {
    string,
    bool,
    i64,
    f64,
}

JSONInner :: union {
    []^JSONResult,
    JSONValue
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

    lines = strings.split_lines(file_as_string)
    if lines == nil do ok = false
    
    return lines, ok
}

parse_json_from_file :: proc(filepath: string) -> (res: []^JSONResult, ok: bool) #optional_ok {

    lines: []string = read_lines_from_file(filepath)
    if lines == nil {
        log.errorf("%s: Could not read lines from file: %s", #procedure, filepath)
        return nil, false
    }
    
    parsed_json: [dynamic]^JSONResult = parse_json_into_arr(lines)
    return parsed_json[:]
}

@(private)
parse_json_into_arr :: proc(lines: []string) -> (res: [dynamic]^JSONResult, ok: bool) {

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
                splitByAssignment: []string = parse_json_key_value(key_line)
                assert(len(splitByAssignment) == 2)

                line_res := new(JSONResult)
                line_res.key := parse_key(splitByAssignment[0], #procedure)
                line_res.value := parse_multi_inner(splitByAssignment[1], #procedure)
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
            splitByAssignment: []string = parse_json_key_value(key_line)
            assert(len(splitByAssignment) == 2)

            line_res := new(JSONResult)
            line_res.key := parse_key(splitByAssignment[0], #procedure)
            line_res.value := parse_inner(splitByAssignment[1], #procedure)
            append(&res, line_res)
        }
}

@(private)
parse_json_key_value :: proc(line: string) -> (result: []string) {
    inQuotes := false
    result := [2]string{"", ""}
    for char, i in line {
        if char == '\"' do inQuotes = !inQuotes
        else if char == ':' && !inQuotes {
            result[0] = strings.substring(0, i)
            result[1] = strings.substring(i + 1, len(line))
        }
    }

    return result
}

@(private)
parse_key :: proc(key_line, call_proc: string) -> (key: string, ok: bool) {
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

@(private)
parse_inner :: proc(value_line, call_proc: string) -> (inner: JSONInner, ok: bool) #optional_ok {
    value, ok := parse_value(value_line)
    if !ok {
        log.errorf("%s: JSON parsing error: Value of %s was not able to be parsed", call_proc, value_line)
        return nil, false
    }
    inner: JSONInner = []JSONValue{value}
    return inner, true
}

@(private)
parse_value :: proc(value_line, call_proc: string) -> (value: JSONValue, ok: bool) {
    
    trimmed_line := strings.trim_space(value_line)
    #partial switch(get_data_fmt(trimmed_line, call_proc)) {
        case .BOOL:
            value = trimmed_line == "true"
        case .INT:
            value, ok = strconv.parse_i64(trimmed_line)
        case .FLOAT:
            value, ok = strconv.parse_f64(trimmed_line)
        case .STRING:
            value = trimmed_line
    }

    return value, ok
}

@(private)
parse_multi_inner :: proc(value_line, call_proc: string) -> (value: JSONInner, ok: bool) #optional_ok {
    // Grab assignments from inside brackets, split them and recurse parse_json_into_arr
    assign_starts_at, assign_ends_at: int = 0
    for char, i in value_line {
        if char == '{' do assign_starts_at = i
        else if char == '}' do assign_ends_at = i
    }

    if assign_starts_at >= assign_ends_at {
        log.errorf("%s: JSON parsing error: Inline value brackets are flipped in %s", call_proc, value_line)
        return nil, false
    }

    assignments = strings.substring(value_line, assign_starts_at, assign_ends_at + 1)
    statements = strings.split(assignments, ",")

    arr, ok := parse_json_into_arr(statements)
    if !ok do return nil, false

    return statements[:], true
}

@(private)
get_data_fmt :: proc(value_str: string, call_proc: string) -> (data_type: AcceptedValues, ok: bool) {
    if strings.count(value_str, "\"") == 2 {
        return AcceptedValues.STRING, true
    }
    else if strings.contains(value_str, "true") || strings.contains(value_str, "false") {
        return AcceptedValues.BOOL, true
    }
    else if unicode.is_number(value_str) {
        if strings.contains(value_str, ".") do return AcceptedValues.FLOAT, true
        else do return AcceptedValues.INT, true
    }
    else {
        log.errorf("%s: JSON paring error: Invalid type for data given: %s", call_proc, value_str)
        return typeid_of(typeid), false
    }
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
