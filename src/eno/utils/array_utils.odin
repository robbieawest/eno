package utils

import dbg "../debug"

import "base:intrinsics"

import "core:testing"
import "core:mem"
import "core:slice"

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
    Allows you to give multiple indices
*/
remove_from_dynamic :: proc(arr: ^$T/[dynamic]$E, indices: ..int) -> (ok: bool) {
    indices := slice.clone(indices)
    defer delete(indices)
    slice.sort(indices)


    for index, j in indices {
        if sorted_check_duplicate(indices, j) {
            dbg.debug_point(dbg.LogLevel.ERROR, "Index %d is a duplicate, ignoring", index)
            continue
        }

        if index_in_bounds(index, len(arr)) {
            dbg.debug_point(dbg.LogLevel.ERROR, "Index %d is out of range of length %d", index, len(arr))
            return
        }

        i := 0
        for i = i; index < len(arr) - 1 - j; i += 1 {
            bit_swap(&arr[i], &arr[i + 1])  // Bubble up unwanted value
        }
        arr[i] = 0  // Default out end space
    }

    (transmute(^mem.Raw_Dynamic_Array)arr).len -= len(indices)

    return true
}

index_in_bounds :: proc(#any_int index: int, length: int) -> (in_bounds: bool) {
    return index >= 0 && index < length
}

sorted_check_duplicate :: proc(slice: $T/[]$E, #any_int index: int) -> (duplicate: bool) {
    if !index_in_bounds(index, len(slice)) do return false

    return (index > 0 && slice[index - 1] == slice[index]) || (index < len(slice) - 1 && slice[index + 1] == slice[index])
}


@(test)
remove_from_dynamic_test :: proc(t: ^testing.T) {

    arr := make([dynamic]u32, 10)
    append_elems(&arr, 10, 9, 32, 2, 3, 90, 26, 10, 1, 2)

    ok := remove_from_dynamic(&arr, 2, 5, 6, 7, 1)
    testing.expect(t, ok)
    testing.expect_value(t, len(arr), 5)
    testing.expect_value(t, arr[0], 10)
    testing.expect_value(t, arr[1], 2)
    testing.expect_value(t, arr[2], 3)
    testing.expect_value(t, arr[3], 1)
    testing.expect_value(t, arr[4], 2)
}