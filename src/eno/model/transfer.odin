package model

import "core:log"

// This class defines data transfer
// Currently implemented for parsing and representing JSON input

JSONInner :: union {
    ^JSONResult,
    any
}

JSONResult :: struct { //Size will not be known at runtime apparently
    key: string,
    value: JSONInner
}

parse_json_from_file :: proc(filepath: string) -> (result: ^JSONResult) {

}

destroy_json_result :: proc(result: ^JSONResult) {
    destroy_json_inner(result.value)
    free(result)
}

@(private)
destroy_json_inner :: proc(inner: ^JSONInner) {
    json_res, ok := inner.(^JSONResult)
    if ok do destroy_json_result(json_res)
    else {
        any_res, ok := inner.(any)
        if !ok do log.errorf("Type error should not happen in %s", #file)
        free(any_res.data)
        delete(any_res)
    }
}
