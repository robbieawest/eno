package utils

import "core:testing"
import "core:math/linalg"

@(require_results)
pow_u32 :: proc(base, exp: u32) -> (res: u32) {
    if exp <= 0 do return
    return u32(fast_exponentation(i64(base), exp))
}

@(require_results)
pow_i32 :: proc(base, exp: i32) -> (res: f32) {
    if exp < 1 do return 1 / f32(fast_exponentation(i64(base), u32(-exp)))
    else do return f32(fast_exponentation(i64(base), u32(exp)))
}

@(require_results)
pow_variable :: proc(base, exp: $T, $out: typeid) -> (res: out) {
    switch T {
        case u32: return cast($out)pow_u32(base, exp)
        case i32: return cast($out)pow_i32(base, exp)
    }
}


@(private)
fast_exponentation :: proc(base: i64, exp: u32) -> (res: i64) {
    current_exp := exp
    base := base
    res = 1

    for current_exp > 0 {
       if current_exp & 1 == 1 {
           res *= base
       }

        base *= base
        current_exp >>= 1
    }

    return
}

@(test)
fast_expo_test :: proc(t: ^testing.T) {
    testing.expect_value(t, fast_exponentation(3, 3), 27)
}

@(test)
pow_test :: proc(t: ^testing.T) {
    testing.expect_value(t, pow_u32(2, 3), 8)
    testing.expect_value(t, pow_i32(2, -2), 0.25)
}


// Does not support negative scales
// Nobody cares about negative scales
decompose_transform :: proc(mat: matrix[4, 4]f32) -> (trans: [3]f32, scale: [3]f32, rot: quaternion128) {
    trans = { mat[0, 3], mat[1, 3], mat[2, 3] }
    scale = {
        linalg.length([3]f32{ mat[0, 0], mat[1, 0], mat[2, 0] }),
        linalg.length([3]f32{ mat[0, 1], mat[1, 1], mat[2, 1] }),
        linalg.length([3]f32{ mat[0, 2], mat[1, 2], mat[2, 2] }),
    }

    rot_mat := mat
    rot_mat[0, 3] = 0
    rot_mat[1, 3] = 0
    rot_mat[2, 3] = 0

    for i in 0..<3 {
        for j in 0..<3 {
            rot_mat[i, j] /= scale[j]
        }
    }

    rot = linalg.quaternion_from_matrix4_f32(rot_mat)
    return
}