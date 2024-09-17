package model

import "core:log"
import "core:os"
import "core:strings"
import "core:unicode"
import "core:strconv"

// This file defines data transfer

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

// Currently implemented for parsing and representing JSON input
// *none of this is tested yet

AcceptedValues :: enum { STRING, BOOL, INT, FLOAT, LIST}
JSONValue :: union {
    string,
    bool,
    i64,
    f64,
    []JSONValue // Check cleanup for this
}

JSONInner :: union {
    []^JSONResult,
    JSONValue
}

JSONResult :: struct {
    key: string,
    value: JSONInner
}


parse_json :: proc { parse_json_from_file, parse_json_from_lines }

parse_json_from_file :: proc(filepath: string) -> (res: ^JSONResult, ok: bool) #optional_ok {

    lines: []string = read_lines_from_file(filepath)
    if lines == nil {
        log.errorf("%s: Could not read lines from file: %s", #procedure, filepath)
        return nil, false
    }
    
    return parse_json_from_lines(lines)
}

@(private)
parse_json_from_lines :: proc(lines: []string) -> (res: ^JSONResult, ok: bool) {
    res := new (JSONResult)
    res.key = ""
    res.value, ok = parse_json_document(lines)
    return res, ok
}

@(private)
parse_json_document :: proc(lines: []string) -> (res: JSONInner, ok: bool) {

    //assume single assignment per line, unless all assignments for an inner JSON document are described inline with '{...}'
    
    continued_bracket_start := -1
    json_results := [dynamic]JSONResult{}

    for line, i in lines {
        line := strings.trim_space(line)
        
        if continued_brackets_start != -1 && !strings.contains(line, "}"){
            if strings.ends_with(line, "}"){
                log.errorf("%s: JSON parsing error: Line cannot end with a single '}' without any comma indicating the next", #procedure)
                return nil, false
            }

            if strings.ends_with(line, "},") {
                // recursively call this procedure to figure out the JSONInner value for the bracketed region
                json_results[len(json_results) - 1].value = parse_json_document(strings.substring(lines, continued_bracket_start, i + 1))
                cotinued_bracket_start = -1
            }
            continue
        }

        //Parse some basic features

        containsAssignment, inQuotes, bracketOpens, bracketCloses := false
        nEndCommas := 0

        for char, j in line {
            #partial switch char {
                case '\"' :inQuotes = !inQuotes
                case ':': if !inQuotes do containsAssignment = true
                case '{': bracketOpens = true
                case '}': bracketCloses = true
                case ',': if !inQuotes do nEndCommas += 1
            }
        }

        //--

        line_res := new(JSONResult)
        splitByAssignment: []string = parse_json_key_value(key_line)
        assert(len(splitByAssignment) == 2)

        line_res.key := parse_key(splitByAssignment[0], #procedure)

        if bracketOpens { //Contains recursive json document inline or across the next lines
            if bracketCloses do line_res.value := parse_multi_inner(splitByAssignment[1], #procedure) // JSONInner described in the same lin
            else do continued_bracket_start = i // JSONInner described over the next few lines
        }
        else { //Single assignment
            if (nEndCommas == 0) {
                log.errorf("%s: JSON parsing error: No commas to designate line end", #procedure)
                return nil, false
            }
            else if (nEndCommas > 1) {
                log.errorf("%s: JSON parsing error: Multiple commas designating line end", #procedure)
                return nil, false
            }
            
            // End of recursion, given a direct value (no more JSONInner)
            line_res.value := parse_inner(splitByAssignment[1], #procedure)
        }

        append(&json_results, line_res)
    }

    res := json_results[:]
    return res, true
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

    return arr[:], true
}

destroy_json :: proc {destroy_json_result, destroy_json_results }

@(private)
destroy_json_output :: proc(results: JSON) {
    for result in results do destroy_json_result(result)
}

@(private)
destroy_json_result :: proc(result: ^JSONResult) {
    destroy_json_inner(result.value)
    free(result)
}

@(private)
destroy_json_inner :: proc(inner: ^JSONInner) {
    json_res, ok := inner.([]^JSONResult)
    if ok do for results in json_res { destroy_json_result(results) }
    else {
        any_res, ok := inner.(any)
        if !ok do log.errorf("Type error should not happen in %s", #procedure)
        free(any_res.data)
        delete(any_res)
    }
}
