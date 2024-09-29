package model

import "core:log"
import "core:mem"
import "core:strings"
import "core:unicode"
import "core:strconv"
import "core:testing"
import "core:fmt"
import "core:slice"
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
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "{\n")

    json_to_string_internal(&builder, "\t", result)

    strings.write_string(&builder, "}\n")
    return strings.to_string(builder)
}

//@(test)
//json_to_string_test :: proc(t: ^testing.T) {
 //   result := new(JSONResult)ture is based on a misperception of the h
 //   result.key = ""
 //   result.value = JSONInner { []^Jnter address of 'builder' SONResult { }}
//}



// -- json parsing --

parse_json :: proc { parse_json_from_file, parse_json_from_lines }

parse_json_from_file :: proc(filepath: string) -> (res: ^JSONResult, ok: bool) #optional_ok {

    lines: []string = utils.read_lines_from_file(filepath)
    defer delete(lines)

    if lines == nil {
        log.errorf("%s: Could not read lines from file: %s", #procedure, filepath)
        return nil, false
    }
    
    return parse_json_from_lines(lines)
}


parse_json_from_lines :: proc(lines: []string) -> (res: ^JSONResult, ok: bool) {
    lines := slice.filter(lines, proc(s: string) -> bool { return len(s) != 0 })
    defer delete(lines)

    res = new (JSONResult)
    res.key = ""
    res.value, ok = parse_json_document(lines, true)
    return res, ok
}

@(private)
parse_json_document :: proc(lines: []string, root: bool) -> (res: JSONInner, ok: bool) {

    //assume single assignment per line, unless all assignments for an inner JSON document are described inline with '{...}'
    
    continued_bracket_start := -1
    json_results := [dynamic]^JSONResult{}
    defer delete(json_results)

    log.infof("lines: %s", lines)

    for line, i in lines {
        line := strings.trim_space(line)
        
        if continued_bracket_start != -1 {
            log.info("in continued")
            log.infof("line in continued: %s", line)
            ends_with_no_comma := strings.ends_with(line, "}")
            if ends_with_no_comma && i != len(lines) - 1 {
                log.error("bad")
                log.errorf("%s: JSON parsing error: Line %s cannot end with a single '}' without any comma indicating the next", #procedure, line)
                return nil, false
            }

            if strings.ends_with(line, "},") || ends_with_no_comma {
                // recursively call this procedure to figure out the JSONInner value for the bracketed region
                log.info("Recursively calling")
                resultant_inner := parse_json_document(lines[continued_bracket_start+1:i], false) or_return
                resultant, ok := resultant_inner.([]^JSONResult)
                if !ok {
                    log.errorf("Unexpected result")
                    return nil, false
                }

                if root {
                    err := reserve(&json_results, len(resultant))
                    if err != mem.Allocator_Error.None {
                        log.errorf("Allocator error when reserving into results")
                        return nil, false
                    }

                    for inner in resultant do append(&json_results, inner) 
                }
                else {
                    json_results[len(json_results) - 1].value = resultant
                }

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
        
        if bracketOpens { //Contains recursive json document inline or across the next lines
            if bracketCloses {
                key_input, value_input := split_assignment(line)
                line_res.key = parse_key(key_input, #procedure) or_return
                line_res.value = parse_multi_inner(value_input, #procedure) or_return // JSONInner described in the same line
            }
            else do continued_bracket_start = i // JSONInner described over the next few lines
        }
        else if !bracketCloses { //Single assignment
            if !containsAssignment {
                log.errorf("%s: JSON parsing error: Assignment expected, ':' not found.", #procedure)
                return nil, false
            }

            key_input, value_input := split_assignment(line)
            line_res.key = parse_key(key_input, #procedure) or_return

            if (nEndCommas == 0 && i != len(lines) - 1) {
                log.errorf("%s: JSON parsing error: No commas to designate line end", #procedure)
                return nil, false
            }
            else if (nEndCommas > 1) {
                log.errorf("%s: JSON parsing error: Multiple commas designating line end", #procedure)
                return nil, false
            }
            
            // End of recursion, given a direct value (no more JSONInner)
            log.infof("split by assignment 1: %s", value_input)
            line_res.value = parse_value(value_input, #procedure) or_return
        }
        
        if len(line_res.key) != 0 do append(&json_results, line_res)
    }

    res = json_results[:]
   // log.infof("inner after %s finish: %s", #procedure, print_inner(res))
    return res, true
}

@(test)
json_test_simple :: proc(t: ^testing.T) {
   
    filepath :: "resources/jsontest1.txt"
    result, ok := parse_json(filepath)
    defer destroy_json(result)

    testing.expect(t, ok)
    //log.infof("json to string: %s\n", json_to_string(result))
   // log.infof("print json result: %s\n", print_json(result))
}

@(private)
print_json :: proc(result: ^JSONResult) -> string {
    if result == nil {
        //log.errorf("Result is nil in %s", #procedure)
        return "nil"
    }
    return fmt.aprintf("{{ key: \"%s\", inner: %s }}", result.key, print_inner(result.value))
}

@(private)
print_inner :: proc(inner: JSONInner) -> string {
    if inner == nil {
      //  log.errorf("Inner is nil in %s", #procedure)
        return "nil"
    }

    list, ok := inner.([]^JSONResult)
    if ok {
        builder := strings.builder_make()

        strings.write_string(&builder, " [ ")

        for &res in list do strings.write_string(&builder, fmt.aprintf("%s, ", print_json(res)))

        strings.pop_rune(&builder)
        strings.pop_rune(&builder)

        strings.write_string(&builder, " ] ")
        return strings.to_string(builder)
    }
    return fmt.aprintf("%v", inner.(JSONValue))
}

// -- 


@(private)
split_assignment :: proc(line: string) -> (key, value: string) {
    inQuotes := false
    for char, i in line {
        if char == '\"' do inQuotes = !inQuotes
        else if char == ':' && !inQuotes {
            log.infof("found colon")
            return line[0:i], line[i+1:]
        }
    }
    
    log.errorf("Could not find assignment in line: %s", line)
    return "", ""
}

@(private)
parse_key :: proc(key_line, call_proc: string) -> (key: string, ok: bool) {
    if key_line == "" do return key_line, true
    key_line := strings.trim_space(key_line)

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
    
    if len(value_line) == 0 {
        log.errorf("%s: JSON parsing error: Value input is empty on assignment in line: %s", call_proc, value_line)
        return value, false
    }

    log.infof("value line: \"%s\"", value_line)

    trimmed_line := strings.trim_space(value_line)

    last_ind := len(trimmed_line) - 1
    line := trimmed_line[0:trimmed_line[last_ind] == ',' ? last_ind : last_ind + 1]

    log.infof("trimmed line: '%s'", line)

    switch(utils.get_string_encoded_type(line)) {
        case .TRUE:
            value = true
        case .FALSE:
            value = false
        case .NEG_INT, .POS_INT:
            value, ok = strconv.parse_i64(line)
        case .NEG_REAL, .POS_REAL:
            value, ok = strconv.parse_f64(line)
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

    return parse_json_document(statements, false) //May need to be true depending
}

destroy_json :: proc(result: ^JSONResult) {
    delete(result.key)
    destroy_json_inner(&result.value)
    free(result)
}

destroy_json_inner :: proc(inner: ^JSONInner) {
    if val, ok := inner.([]^JSONResult); ok do for result in val do destroy_json(result)
    else if val, ok := inner.(JSONValue); ok do destroy_json_value(val)
    //else nil
}

destroy_json_value :: proc(value: JSONValue) {
    if val, ok := value.(string); ok do delete(val)
    else if val, ok := value.([]JSONValue); ok do for v in val do destroy_json_value(value)
}
