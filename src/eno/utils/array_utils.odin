package utils

import "core:testing"
import "core:mem"

// Utils package must not depend on any other package
// If certain functionality needs to be dependent on another package, just make another package
// ^ See file_utils


append_n :: proc(dynamic_arr: ^$T/[dynamic]$E, n: u32) {
    reserve(dynamic_arr, n)
    for i in 0..<n {
        def: E 
        append(dynamic_arr, def)
    }
}


@(test)
append_n_defaults_test :: proc(t: ^testing.T) {
    //leaking?
s_slice := []f32{0.32, 0.12, 0.58}
    s_expected_end_slice := []f32{0.32, 0.12, 0.58, 0.0, 0.0, 0.0}
    slice := make([dynamic]f32, 0)
    expected_end_slice := make([dynamic]f32, 0)
    append(&slice, ..s_slice)
    append(&expected_end_slice, ..s_expected_end_slice)
    defer delete(expected_end_slice)
    defer delete(slice)

    append_n(&slice, 3)

    testing.expect_value(t, len(slice), len(expected_end_slice))
    for i in 0..<len(slice) do testing.expect_value(t, slice[i], expected_end_slice[i])
}
