package utils

import "core:testing"

/* likely not needed
remove_indexes_from_slice :: proc(slice: ^$T/[]$E, indexes: []int) -> (result: []T) {
    data: [dynamic]E
    
}
*/

//Allocates a new dynamic array and slices it based on the input slice. Result must then be freed
remove_index_from_slice :: proc(slice: ^$T/[]$E, index : int) -> (result: T) {
    data: [dynamic]E
    reserve(&data, 2)
    
    first_slice: T = slice[0:index]
    second_slice: T = slice[index+1:]
    
    for e_val in first_slice do append(&data, e_val)
    for e_val in second_slice do append(&data, e_val)

    return data[:]
}

@(test)
remove_index_test :: proc(t: ^testing.T) {
    slice := []string{"hey", "guys", "its", "me" }
    removed: []string = remove_index_from_slice(&slice, 2)
    defer delete(removed)

    removed_expected: []string = []string{"hey", "guys", "me"}

    testing.expect_value(t, len(removed_expected), len(removed))

    for i := 0; i < len(removed); i += 1 do testing.expect_value(t, removed[i], removed_expected[i])
}
