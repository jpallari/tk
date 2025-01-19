package cstr

Builder :: struct {
    buffer:     ^[dynamic]u8,
    last_start: int,
    cur_len:    int,
}

append_string :: proc(b: ^Builder, s: string) -> (added: int, ok: bool) {
    if len(s) + len(b.buffer) + 1 > cap(b.buffer) {
        return 0, false
    }
    added = append(b.buffer, ..transmute([]u8)s)
    b.cur_len += added
    ok = true
    return
}

pop_cstr :: proc(b: ^Builder) -> (cstr: cstring, ok: bool) {
    if len(b.buffer) == cap(b.buffer) {
        return
    }
    if b.cur_len == 0 {
        return
    }
    append(b.buffer, 0)
    cstr = cstring(&b.buffer[b.last_start])
    b.last_start = b.cur_len + 2
    b.cur_len = 0
    ok = true
    return
}

