package exec

import "base:runtime"
import "core:os"
import "core:strings"
import "core:sys/posix"

@(private)
bytes_to_cstring :: proc(bytes: []u8) -> cstring {
    return cstring(raw_data(bytes))
}

@(private)
count_os_env :: proc() -> int {
    count := 0
    for entry := posix.environ[0];
        entry != nil;
        count, entry =
            count + 1, posix.environ[count] {}
    count -= 1
    return count
}

@(private)
find_cmd_path :: proc(
    cmd_path: ^[dynamic]u8,
    cmd: string,
) -> (
    ok: bool,
    err: runtime.Allocator_Error,
) {
    if len(cmd) == 0 {
        return
    }
    if cmd[0] == '.' || cmd[0] == '/' {
        append(cmd_path, ..transmute([]u8)cmd) or_return
        append(cmd_path, 0) or_return
        ok = true
        return
    }

    path := string(posix.getenv("PATH"))
    if len(path) == 0 {
        path = "/usr/local/bin:/bin:/usr/bin"
    }
    for p in strings.split_iterator(&path, ":") {
        p_bytes := transmute([]u8)p
        cmd_bytes := transmute([]u8)cmd
        append(cmd_path, ..p_bytes) or_return
        append(cmd_path, '/') or_return
        append(cmd_path, ..cmd_bytes) or_return
        append(cmd_path, 0) or_return

        cmd_s := bytes_to_cstring(cmd_path[:])
        ok = posix.access(cmd_s) == .OK
        if ok {
            break
        }
        clear(cmd_path)
    }
    return
}

Cmd_Result :: enum {
    Ok,
    Not_Found,
    Fork_Failed,
    Wait_Failed,
    Exec_Failed,
    Cmd_Failed,
}

Cmd :: struct {
    cmd_path: [dynamic]u8,
    args:     [dynamic]cstring,
    env:      [dynamic]cstring,
}

Params :: struct {
    args:        []string,
    env:         []string,
    inherit_env: bool,
}

init :: proc(
    cmd: ^Cmd,
    params: ^Params,
) -> (
    ok: bool,
    err: runtime.Allocator_Error,
) {
    if len(params.args) == 0 {
        return
    }

    // path
    reserve(&cmd.cmd_path, 2048) or_return
    ok = find_cmd_path(&cmd.cmd_path, params.args[0]) or_return
    if !ok {
        return
    }

    // args
    reserve(&cmd.args, len(params.args) + 1) or_return
    for arg in params.args {
        carg := strings.clone_to_cstring(arg) or_return
        append(&cmd.args, carg) or_return
    }
    append(&cmd.args, nil) or_return

    // join os env
    os_env_count := 0
    if params.inherit_env {
        os_env_count = count_os_env()
    }
    reserve(&cmd.env, len(params.env) + os_env_count + 1) or_return
    if params.inherit_env {
        append(&cmd.env, ..posix.environ[:os_env_count]) or_return
    }
    for entry in params.env {
        centry := strings.clone_to_cstring(entry) or_return
        append(&cmd.env, centry) or_return
    }
    append(&cmd.env, nil) or_return

    ok = true
    return
}

destroy :: proc(cmd: ^Cmd) {
    for arg in cmd.args {
        delete(arg)
    }
    for env in cmd.env {
        delete(env)
    }
    delete(cmd.cmd_path)
    delete(cmd.args)
    delete(cmd.env)
    cmd.cmd_path = nil
    cmd.args = nil
    cmd.env = nil
}

run :: proc(cmd: ^Cmd) -> (status: i32, errno: posix.Errno, res: Cmd_Result) {
    // fork
    child_pid := posix.fork()
    if child_pid == -1 {
        return -1, posix.errno(), .Fork_Failed
    }

    // wait
    if child_pid > 0 {
        options: posix.Wait_Flags
        posix.waitpid(child_pid, &status, options)
        if status < 0 {
            errno = posix.errno()
            res = .Wait_Failed
        } else if status > 0 {
            res = .Cmd_Failed
        }
        return
    }

    // exec
    cmd_path_s := bytes_to_cstring(cmd.cmd_path[:])
    status_c := posix.execve(cmd_path_s, raw_data(cmd.args), raw_data(cmd.env))
    return cast(i32)status_c, posix.errno(), Cmd_Result.Exec_Failed
}
