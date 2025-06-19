package utils

copy_map :: proc(m: map[$K]$V) -> (ret: map[K]V) {
    ret = make(map[K]V, len(m))
    for k, v in m do ret[k] = v
    return
}

bit_swap :: proc(a: ^$T, b: ^T) {
    a^ ^= b^
    b^ ^= b^
    a^ ^= b^
}