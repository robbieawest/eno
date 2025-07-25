package utils

import dbg "../debug"

import "core:testing"
import "core:log"
import "core:mem"
import "core:strings"
import "core:fmt"
import "core:text/regex"

// Utils package must not depend on any other package
// If certain functionality needs to be dependent on another package, just make another package
// ^ See file_utils

// Quite a few of these were made for json conversion, which as a whole is deprecated

/*
//type_checking for conversion
@(deprecated="Used for deprecated package")
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


@(deprecated="Used for deprecated package")
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

@(deprecated="Used for deprecated package")
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

    return real ? (neg ? .NEG_REAL : .POS_REAL) : neg ? .NEG_INT : .POS_INT
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


@(deprecated="Used for deprecated package")
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
@(deprecated="???????????")
substring_internal :: proc(s: string, sub_start, sub_end_exclusive: int) -> (result: string) {
    return s[sub_start:sub_end_exclusive]
}


@(test)
substring_test :: proc(t: ^testing.T) {
    s: string = "heyguysitsmescarcehere"
    s2: string = substring_internal(s, 2, 4)

    log.infof("s2: %v", s2)
}
*/


concat :: proc(string_inp: ..string, allocator := context.allocator) -> string {
    builder := strings.builder_make(0, 10, allocator)

    for str in string_inp do strings.write_string(&builder, str)

    return strings.to_string(builder)
}


@(test)
concat_test :: proc(t: ^testing.T) {
    str1 := "hello, "
    str2 := "world"
    str3 := "!!"
    log.info(concat(str1, str2, str3))
}


concat_cstr :: proc(string_inp: ..cstring) -> (ret: cstring, err: mem.Allocator_Error) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    for str in string_inp do strings.write_string(&builder, string(str))

    return strings.to_cstring(&builder)
}

fmt_append :: proc(arr: ^[dynamic]string, fmt_str: string, args: ..any) {
    new_str := fmt.aprintf(fmt_str, ..args)
    append(arr, new_str)
}


InvalidCharacterMap :: struct {
    char: rune,
    ind: int
}

REGEX_FILEPATH_PATTERN :: "^[a-zA-Z0-9_\\\\/\\.]*$"
REGEX_ALPHANUM_PATTERN :: "^[a-zA-Z0-9_]*$"

regex_match :: proc{ regex_match_no_flags, regex_match_flags }

regex_match_no_flags :: proc(grammar: string, pattern: string) -> (matched: bool) {
    return regex_match_flags(grammar, pattern, {})
}

regex_match_flags :: proc(grammar: string, pattern: string, flags: regex.Flags) -> (matched: bool) {
    expression, err := regex.create(pattern, { .No_Capture })
    if err != nil {
        dbg.log(.ERROR, "Could not create regex match iterator, defaulting to no match")
        return
    }

    _, matched = regex.match(expression, pattern)
    return

    /*
    regex_match_iterator, err := regex.create_iterator(grammar, pattern, { .No_Capture } + flags)
    defer regex.destroy_iterator(regex_match_iterator)
    if err != nil {

    }

    _, _, matched = regex.match_iterator(&regex_match_iterator)
    */
}

@(test)
regex_match_test :: proc(t: ^testing.T) {

    matched := regex_match("ABCdaf932903215/\\.", "^[a-zA-Z0-9_\\\\/\\.]*$")
    testing.expect(t, matched)

    new_matched := regex_match("ABCdaf932903215*&*(*^", "^[a-zA-Z0-9_]*$")
    testing.expect(t, !new_matched)
}

/*
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
*/