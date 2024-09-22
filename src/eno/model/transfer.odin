package model

import "core:log"
import "core:strings"
import "core:unicode"
import "core:strconv"
import "core:testing"
import "core:fmt"
import "../utils"

// This file defines data transfer


// Currently implemented for parsing and representing JSON input
// *none of this is tested yet

AcceptedValues :: enum { STRING, BOOL, INT, FLOAT, LIST}
JSONValue :: union {
    string,
    bool,
    i64,
    f64,
    []JSONValue // Check cleanup for this *- needs implementation everywhere
}

JSONInner :: union {
    []^JSONResult,
    JSONValue
}

JSONResult :: struct {
    key: string,
    value: JSONInner
}

@(private)
json_to_string_internal :: proc(builder: ^strings.Builder, indent: string, result: ^JSONResult) {

    strings.write_string(builder, utils.concat(indent, "\"", result.key, "\" : "))
    list, is_list := result.value.([]^JSONResult)
    if is_list {
        strings.write_string(builder, "{\n")
        for &inner_result in list do json_to_string_internal(builder, utils.concat(indent, "\t"), inner_result)
        strings.write_string(builder, utils.concat(indent, "},\n"))
    }
    else {
        //is JSONValue
        value, ok := result.value.(JSONValue)
        if !ok {
            log.errorf("%s: Type error when creating string from json", #procedure)
            return
        }
        
        //Print value as simply the odin core fmt out of the value
        value_str := fmt.aprintfln("%v", value)
        defer delete(value_str)

        strings.write_string(builder, utils.concat(value_str, ",\n"))
    }
}

json_to_string :: proc(result: ^JSONResult) -> string {
    builder := strings.builder_make()
    strings.write_string(&builder, "{\n")

    json_to_string_internal(&builder, "\t", result)

    strings.write_string(&builder, "}\n")
    return strings.to_string(builder)
}

//@(test)
//json_to_string_test :: proc(t: ^testing.T) {
 //   result := new(JSONResult)
 //   result.key = ""
 //   result.value = JSONInner { []^Jnter address of 'builder' SONResult { }}
//}



// -- json parsing --

parse_json :: proc { parse_json_from_file, parse_json_from_lines }

parse_json_from_file :: proc(filepath: string) -> (res: ^JSONResult, ok: bool) #optional_ok {

    lines: []string = utils.read_lines_from_file(filepath)
    if lines == nil {
        log.errorf("%s: Could not read lines from file: %s", #procedure, filepath)
        return nil, false
    }
    
    return parse_json_from_lines(lines)
}

@(private)
parse_json_from_lines :: proc(lines: []string) -> (res: ^JSONResult, ok: bool) {
    res = new (JSONResult)
    res.key = ""
    res.value, ok = parse_json_document(lines)
    return res, ok
}

@(private)
parse_json_document :: proc(lines: []string) -> (res: JSONInner, ok: bool) {

    //assume single assignment per line, unless all assignments for an inner JSON document are described inline with '{...}'
    
    continued_bracket_start := -1
    json_results := [dynamic]^JSONResult{}

    log.infof("lines: %s", lines)

    for line, i in lines {
        line := strings.trim_space(line)
        
        if continued_bracket_start != -1 && !strings.contains(line, "}"){
            log.info("in continued")
            ends_with_no_comma := strings.ends_with(line, "}")
            if ends_with_no_comma && i != len(lines) - 1 {
                log.errorf("%s: JSON parsing error: Line % scannot end with a single '}' without any comma indicating the next", #procedure, line)
                return nil, false
            }

            if strings.ends_with(line, "},") || ends_with_no_comma {
                // recursively call this procedure to figure out the JSONInner value for the bracketed region
                json_results[len(json_results) - 1].value = parse_json_document(lines[continued_bracket_start:i+1]) or_return
                continued_bracket_start = -1
            }
            continue
        }

        //Parse some basic features

        containsAssignment, inQuotes, bracketOpens, bracketCloses := false, false, false, false
        nEndCommas := 0
        log.infof("line: %s", line)
        for char, j in line {
            switch char {
                case '"': inQuotes = !inQuotes
                case ':': if !inQuotes do containsAssignment = true
                case '{': bracketOpens = true
                case '}': bracketCloses = true
                case ',': if !inQuotes do nEndCommas += 1
            }
        }

        log.infof("contas: %v, inqu: %v, brao: %v, brac: %v", containsAssignment, inQuotes, bracketOpens, bracketCloses)
    
        //--

        line_res := new(JSONResult)
        splitByAssignment: []string = parse_json_key_value(line)
        assert(len(splitByAssignment) == 2)

        line_res.key = parse_key(splitByAssignment[0], #procedure) or_return

        if bracketOpens { //Contains recursive json document inline or across the next lines
            if bracketCloses do line_res.value = parse_multi_inner(splitByAssignment[1], #procedure) or_return // JSONInner described in the same lin
            else do continued_bracket_start = i // JSONInner described over the next few lines
        }
        else if !bracketCloses { //Single assignment
            if (nEndCommas == 0) {
                log.errorf("%s: JSON parsing error: No commas to designate line end", #procedure)
                return nil, false
            }
            else if (nEndCommas > 1) {
                log.errorf("%s: JSON parsing error: Multiple commas designating line end", #procedure)
                return nil, false
            }
            
            // End of recursion, given a direct value (no more JSONInner)
            line_res.value = parse_value(splitByAssignment[1], #procedure) or_return
        }

        append(&json_results, line_res)
    }

    res = json_results[:]
    return res, true
}

@(test)
json_test_simple :: proc(t: ^testing.T) {
   
    filepath :: "resources/jsontest1.txt"
    result, ok := parse_json(filepath)
    testing.expect(t, ok)
    
    log.info("json to string: %s\n", json_to_string(result))
    log.infof("jsonresult: %v", result)
}

// -- 


@(private)
parse_json_key_value :: proc(line: string) -> (result: []string) {
    inQuotes := false
    result = []string{"", ""}
    for char, i in line {
        if char == '\"' do inQuotes = !inQuotes
        else if char == ':' && !inQuotes {
            result[0] = line[0:i]
            result[1] = line[i+1:len(line)]
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
            if nQuotes <= 1 do nQuotes += 1
            else {
                log.errorf("%s: JSON parsing error: Number of quotes in key is irregular", call_proc)
                return "", false
            }
        }
        else if nQuotes != 1 {
            // If not inside the quotes
            log.errorf("%s: JSON parsing error: Irregular character when parsing key at index: %d", call_proc, i)
            return "", false
        }
        else do strings.write_rune(&key_builder, char)
    }

    return strings.to_string(key_builder), true
}

@(private)
parse_value :: proc(value_line, call_proc: string) -> (value: JSONValue, ok: bool) {
    
    trimmed_line := strings.trim_space(value_line)
    switch(utils.get_string_encoded_type(trimmed_line)) {
        case .TRUE:
            value = true
        case .FALSE:
            value = false
        case .NEG_INT, .POS_INT:
            value, ok = strconv.parse_i64(trimmed_line)
        case .NEG_REAL, .POS_REAL:
            value, ok = strconv.parse_f64(trimmed_line)
        case .STRING:
            value = trimmed_line
        case .NOT_APPLICABLE:
            log.errorf("%s: JSON parsing error: Invalid format when parsing value on the line: %s", call_proc, value_line)
            return value, false
    }

    return value, ok
}

@(private)
parse_multi_inner :: proc(value_line, call_proc: string) -> (value: JSONInner, ok: bool) #optional_ok {
    // Grab assignments from inside brackets, split them and recurse parse_json_into_arr
    assign_starts_at, assign_ends_at := 0, 0
    for char, i in value_line {
        if char == '{' do assign_starts_at = i
        else if char == '}' do assign_ends_at = i
    }

    if assign_starts_at >= assign_ends_at {
        log.errorf("%s: JSON parsing error: Inline value brackets are flipped in %s", call_proc, value_line)
        return nil, false
    }

    assignments := value_line[assign_starts_at:assign_ends_at+1]
    statements := strings.split(assignments, ",")

    return parse_json_document(statements)
}

destroy_json :: proc(result: ^JSONResult) {
    destroy_json_inner(&result.value)
    free(result)
}

destroy_json_inner :: proc(inner: ^JSONInner) {
    list_val, ok := inner.([]^JSONResult)
    if ok do for result in list_val do destroy_json(result)
    
    free(inner)
}
