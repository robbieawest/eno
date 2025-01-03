package utils

import "core:testing"
import "core:log"
import "core:strings"
import "core:mem"
import "core:fmt"


// Below all deprecated

//type_checking for conversion
is_string :: proc(s: string) -> bool {
    in_quotes := false
    n_quotes := 0
    for c in s {
        if c == '"' {
            in_quotes = !in_quotes
            n_quotes += 1
        }
        else if !in_quotes && c != ' ' do return false
    }

    return n_quotes == 2
}


@(test)
test_is_string :: proc(t: ^testing.T) {
    testing.expect_value(t, is_string("\"hey guys its me scarce here\""), true)
    testing.expect_value(t, is_string("hey guys \"hey guys its me scarce here\""), false)
    testing.expect_value(t, is_string("hey guys \"hey guys its me scarce here\" hey guys"), false)
    testing.expect_value(t, is_string("hey guys \"hey guys \"its me scarce here\" hey guys"), false)
    testing.expect_value(t, is_string("false"), false)
    testing.expect_value(t, is_string("1.231"), false)
}


is_bool :: proc(s: string) -> StringTypeResult {
    s := strings.trim_space(s)
    return s == "true" ? .TRUE : s == "false" ? .FALSE : .NOT_APPLICABLE
}


@(test)
test_is_bool :: proc(t: ^testing.T) {
    testing.expect_value(t, is_bool("false"), StringTypeResult.FALSE)
    testing.expect_value(t, is_bool("true"), StringTypeResult.TRUE)
    testing.expect_value(t, is_bool("   true      "), StringTypeResult.TRUE)
    testing.expect_value(t, is_bool("   false          "), StringTypeResult.FALSE)
    testing.expect_value(t, is_bool("truetrue"), StringTypeResult.NOT_APPLICABLE)
    testing.expect_value(t, is_bool("falsefalse"), StringTypeResult.NOT_APPLICABLE)
    testing.expect_value(t, is_bool("falsefalse"), StringTypeResult.NOT_APPLICABLE)
    testing.expect_value(t, is_bool("1.3535"),  StringTypeResult.NOT_APPLICABLE)
}


// STRING here is defined as "\"{...}\"", NOT_APPLICABLE is for example "nanvaluehere", the STRING equivalent would be "\"nanvaluehere\""
StringTypeResult :: enum { NOT_APPLICABLE, TRUE, FALSE, STRING, NEG_INT, POS_INT, NEG_REAL, POS_REAL }


is_number :: proc(s: string) -> StringTypeResult {
    if len(s) == 0 do return .NOT_APPLICABLE
    neg := s[0] == '-'

    real := false
    loop: for r in s[1:] {
        switch r {
        case '0'..='9':
        case '.': 
            real = true
        case:
            return .NOT_APPLICABLE
        }
    }

    return real ? neg ? .NEG_REAL : .POS_REAL : neg ? .NEG_INT : .POS_INT
}


@(test)
is_number_test :: proc(t: ^testing.T) {
    testing.expect_value(t, is_number("565.142"), StringTypeResult.POS_REAL)
    testing.expect_value(t, is_number("-123424.3512"), StringTypeResult.NEG_REAL)
    testing.expect_value(t, is_number("38922"), StringTypeResult.POS_INT)
    testing.expect_value(t, is_number("-2556235"), StringTypeResult.NEG_INT)
    testing.expect_value(t, is_number("45624356-2556235"), StringTypeResult.NOT_APPLICABLE)
    testing.expect_value(t, is_number("hey guys its me scarce here"), StringTypeResult.NOT_APPLICABLE)
}


get_string_encoded_type :: proc(s: string) -> StringTypeResult {
    if is_string(s) do return .STRING
    bool_res := is_bool(s)
    return bool_res == StringTypeResult.NOT_APPLICABLE ? is_number(s) : bool_res
}


@(test)
string_encoded_type :: proc(t: ^testing.T) {
    testing.expect_value(t, get_string_encoded_type("true"), StringTypeResult.TRUE)
    testing.expect_value(t, get_string_encoded_type("\"hey guys it sme scarce here\""), StringTypeResult.STRING)
    testing.expect_value(t, get_string_encoded_type("565.142"), StringTypeResult.POS_REAL)
    testing.expect_value(t, get_string_encoded_type("-123424.3512"), StringTypeResult.NEG_REAL)
    testing.expect_value(t, get_string_encoded_type("38922"), StringTypeResult.POS_INT)
    testing.expect_value(t, get_string_encoded_type("-2556235"), StringTypeResult.NEG_INT)
    testing.expect_value(t, get_string_encoded_type("45624356-2556235"), StringTypeResult.NOT_APPLICABLE)
    testing.expect_value(t, get_string_encoded_type("hey guys its me scarce here"), StringTypeResult.NOT_APPLICABLE)
}


//useless
@(private)
substring_internal :: proc(s: string, sub_start, sub_end_exclusive: int) -> (result: string) {
    return s[sub_start:sub_end_exclusive]
}


@(test)
substring_test :: proc(t: ^testing.T) {
    s: string = "heyguysitsmescarcehere"
    s2: string = substring_internal(s, 2, 4)

    log.infof("s2: %v", s2)
}


concat :: proc(string_inp: ..string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    for str in string_inp do strings.write_string(&builder, str)

    return string_from_builder(builder)
}


@(test)
concat_test :: proc(t: ^testing.T) {
    str1 := "hello, "
    str2 := "world"
    str3 := "!!"
    log.info(concat(str1, str2, str3))
}


concat_cstr :: proc(string_inp: ..cstring) -> cstring {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    for str in string_inp do strings.write_string(&builder, string(str))

    return strings.to_cstring(&builder)
}


MAX_KEY_BYTES :: 256
@(deprecated="Ass procedure, use string_from_builder instead")
to_string_no_alloc :: proc(b: strings.Builder) -> (result: string, err: mem.Allocator_Error)  {
    // this literally just redoes core:strings functionality
    err = mem.Allocator_Error.None
    if len(b.buf) > MAX_KEY_BYTES do return "", mem.Allocator_Error.Invalid_Argument
    
    stack_bytes: [MAX_KEY_BYTES]u8
    if num_copied := copy_slice(stack_bytes[:], b.buf[:]); num_copied < len(b.buf) do err = mem.Allocator_Error.Out_Of_Memory

    return string(stack_bytes[:]), err
}

/*
    To be used when ownership needs to be taken from builder
    For example a procedure deletes the builder internally and by virtue invalidates the ret string upon strings.to_string(builder)
    This would be used in such an example
*/
string_from_builder :: proc(builder: strings.Builder) -> string {
    return strings.clone_from_bytes(builder.buf[:])
}
