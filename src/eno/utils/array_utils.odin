package utils

import dbg "../debug"

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

/*
    Performs an orderly remove, shuffling items. Does not deallocate memory, only updates the internal length of the array
*/
remove_from_dynamic :: proc(arr: ^$T/[dynamic]$E, index: int) -> ( ok: bool) {
    if index < 0 || index >= len(arr) {
        dbg.debug_point(dbg.LogLevel.ERROR, "Index %d is out of range of length %d", index, len(arr))
        return
    }

    for index := index; index < len(arr) - 1; index += 1 {
        bit_swap(arr[index], arr[index + 1])  // Bubble up unwanted value
    }
    arr[index] = 0  // Default out end space

    raw_arr := transmute(mem.Raw_Dynamic_Array)arr
    raw_arr.len -= 1
    arr = transmute([dynamic]$E)raw_arr

    return true
}