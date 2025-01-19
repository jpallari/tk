package cliopts

import "../retry"
import "core:fmt"
import "core:strconv"
import "core:time"

Action :: enum {
    Run,
}

Global_Flags :: struct {
    help: bool,
}

Run_Flags :: struct {
    args:        []string,
    env:         [dynamic]string,
    inherit_env: bool,
    retry:       retry.Config,
}

Action_Flags :: union {
    Run_Flags,
}

Flags :: struct {
    using global: Global_Flags,
    action:       Action_Flags,
}

print_usage :: proc() {
    // TODO: print usage
    fmt.eprintf("usage\n")
}

@(private)
parse_run :: proc(flags: ^Flags, args: []string) -> bool {
    run_flags: Run_Flags
    run_flags.inherit_env = true
    run_flags.retry = retry.Config {
        max_retries    = 10,
        backoff_base   = 2000 * time.Millisecond,
        backoff_min    = 1000 * time.Millisecond,
        backoff_max    = 30000 * time.Millisecond,
        backoff_jitter = 100 * time.Millisecond,
        backoff_type   = .Constant,
    }
    if err := reserve(&run_flags.env, 1024); err != nil {
        fmt.panicf("run_flags.env allocation failed: %v", err)
    }

    parse: for i := 0; i < len(args); i += 1 {
        arg := args[i]
        switch arg {
        case "--help":
            flags.help = true
            break
        case "--no-inherit-env":
            run_flags.inherit_env = false
        case "--env":
            i += 1
            if _, err := append(&run_flags.env, args[i]); err != nil {
                fmt.panicf("run_flags.env append failed: %v", err)
            }
        case "--backoff":
            i += 1
            d, ok := parse_ms(args[i])
            if !ok {
                fmt.eprintf("invalid format for '--backoff': %v", args[i])
                return false
            }
            run_flags.retry.backoff_base = d
        case "--backoff-min":
            i += 1
            d, ok := parse_ms(args[i])
            if !ok {
                fmt.eprintf("invalid format for '--backoff-min': %v", args[i])
                return false
            }
            run_flags.retry.backoff_min = d
        case "--backoff-max":
            i += 1
            d, ok := parse_ms(args[i])
            if !ok {
                fmt.eprintf("invalid format for '--backoff-max': %v", args[i])
                return false
            }
            run_flags.retry.backoff_max = d
        case "--backoff-jitter":
            i += 1
            d, ok := parse_ms(args[i])
            if !ok {
                fmt.eprintf("invalid format for '--backoff-jitter': %v", args[i])
                return false
            }
            run_flags.retry.backoff_jitter = d
        case "--backoff-type":
            i += 1
            switch args[i] {
            case "constant", "c":
                run_flags.retry.backoff_type = .Constant
            case "linear", "l":
                run_flags.retry.backoff_type = .Linear
            case "exponential", "e":
                run_flags.retry.backoff_type = .Exponential
            case:
                fmt.eprintf("invalid selection for '--backoff-type': %v", args[i])
                return false
            }
        case:
            run_flags.args = args[i:]
            break parse
        }
    }

    flags.action = run_flags
    return true
}

parse_ms :: proc(s: string) -> (duration: time.Duration, ok: bool) {
    v := strconv.parse_int(s) or_return
    duration = cast(time.Duration)v * time.Millisecond
    return
}

parse :: proc(flags: ^Flags, args: []string) -> bool {
    if len(args) <= 1 {
        return false
    }

    // skip arg0
    args := args[1:]

    for arg, i in args {
        switch arg {
        case "-h", "--help":
            flags.help = true
            return true
        case "run":
            return parse_run(flags, args[i + 1:])
        case:
            return false
        }
    }
    return false
}
