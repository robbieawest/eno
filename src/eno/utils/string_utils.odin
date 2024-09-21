package utils

import "core:testing"
import "core:log"
import "core:strings"

//type_checking for conversion
is_string :: proc(s: string) -> bool {
    return strings.count(s, "\"") == 2
}

is_bool :: proc(s: string) -> bool {
    return strings.contains(s, "true") || strings.contains(s, "false")
}

// STRING here is defined as "\"{...}\"", NAN is for example "nanvaluehere", the STRING equivalent would be "\"nanvaluehere\""
StringTypeResult :: enum { NAN, BOOL, STRING, NEG_INT, POS_INT, NEG_REAL, POS_REAL }


is_number :: proc(s: string) -> StringTypeResult {
    if len(s) == 0 do return .NAN
    neg := s[0] == '-'

    real := false
    loop: for r in s[1:] {
        switch r {
        case '0'..='9':
        case '.': 
            real = true
        case:
            return .NAN
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
    testing.expect_value(t, is_number("45624356-2556235"), StringTypeResult.NAN)
    testing.expect_value(t, is_number("hey guys its me scarce here"), StringTypeResult.NAN)
}

get_string_encoded_type :: proc(s: string) -> StringTypeResult {
    if is_string(s) do return .STRING
    else if is_bool(s) do return .BOOL
    return is_number(s)
}

@(test)
string_encoded_type :: proc(t: ^testing.T) {
    testing.expect_value(t, get_string_encoded_type("true"), StringTypeResult.BOOL)
    testing.expect_value(t, get_string_encoded_type("\"hey guys it sme scarce here\""), StringTypeResult.STRING)
    testing.expect_value(t, get_string_encoded_type("565.142"), StringTypeResult.POS_REAL)
    testing.expect_value(t, get_string_encoded_type("-123424.3512"), StringTypeResult.NEG_REAL)
    testing.expect_value(t, get_string_encoded_type("38922"), StringTypeResult.POS_INT)
    testing.expect_value(t, get_string_encoded_type("-2556235"), StringTypeResult.NEG_INT)
    testing.expect_value(t, get_string_encoded_type("45624356-2556235"), StringTypeResult.NAN)
    testing.expect_value(t, get_string_encoded_type("hey guys its me scarce here"), StringTypeResult.NAN)
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


