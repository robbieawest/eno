package math_utils

import "core:testing"

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