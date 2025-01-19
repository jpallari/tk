package main

import "core:fmt"
import "core:os"
import "core:time"
import "cliopts"
import "exec"
import "retry"

exec_cmd_retryable :: proc(cmd: ^exec.Cmd) -> (i32, retry.Status) {
    status, errno, res := exec.run(cmd)
    retry: retry.Status
    switch res {
    case .Ok:
        retry = .Ok
    case .Cmd_Failed:
        retry = .Fail
    case .Not_Found, .Wait_Failed, .Fork_Failed, .Exec_Failed:
        retry = .Fatal
    }
    return status, retry
}

action_run :: proc(global: ^cliopts.Global_Flags, run: ^cliopts.Run_Flags) -> i32 {
    cmd: exec.Cmd
    cmd_params := exec.Params {
        args = run.args,
        env = run.env[:],
        inherit_env = run.inherit_env,
    }

    ok, err := exec.init(&cmd, &cmd_params)
    if !ok || err != .None {
        fmt.panicf("command init failed: %v", err)
    }

    status: i32
    status, ok = retry.run(&run.retry, exec_cmd_retryable, &cmd)
    if !ok {
        fmt.eprintf("command failed with code: %v\n", status)
    }
    return status
}

main_with_code :: proc() -> int {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)

    flags: cliopts.Flags
    flags_parsed := cliopts.parse(&flags, os.args)
    if !flags_parsed || flags.help || flags.action == nil {
        cliopts.print_usage()
        return 0 if flags_parsed else 1
    }

    status: i32
    switch &action in flags.action {
    case cliopts.Run_Flags:
        status = action_run(&flags.global, &action)
    }

    return cast(int)status
}

main :: proc() {
    os.exit(main_with_code())
}
