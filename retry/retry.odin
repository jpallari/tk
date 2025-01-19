package retry

import "core:math"
import "core:math/rand"
import "core:time"

Backoff_Type :: enum {
    Constant,
    Linear,
    Exponential,
}

Config :: struct {
    max_retries:    uint,
    backoff_base:   time.Duration,
    backoff_min:    time.Duration,
    backoff_max:    time.Duration,
    backoff_jitter: time.Duration,
    backoff_type:   Backoff_Type,
}

Status :: enum {
    Ok,
    Fail,
    Fatal,
}

@(private)
gen_jitter :: proc(max_jitter: time.Duration) -> time.Duration {
    jitter := rand.int63_max(cast(i64)max_jitter)
    return cast(time.Duration)jitter
}

@(private)
backoff_time_constant :: proc(cfg: ^Config) -> time.Duration {
    d := cfg.backoff_base + gen_jitter(cfg.backoff_jitter)
    return math.clamp(d, cfg.backoff_min, cfg.backoff_max)
}

@(private)
backoff_time_linear :: proc(
    attempt: uint,
    cfg: ^Config,
) -> time.Duration {
    d :=
        cfg.backoff_base * cast(time.Duration)attempt +
        gen_jitter(cfg.backoff_jitter)
    return math.clamp(d, cfg.backoff_min, cfg.backoff_max)
}

@(private)
backoff_time_exponential :: proc(
    attempt: uint,
    cfg: ^Config,
) -> time.Duration {
    coeff := 1 << attempt
    d :=
        cfg.backoff_min * cast(time.Duration)coeff +
        gen_jitter(cfg.backoff_jitter)
    return math.clamp(d, cfg.backoff_min, cfg.backoff_max)
}

@(private)
backoff_time :: proc(
    attempt: uint,
    cfg: ^Config,
) -> (
    duration: time.Duration,
) {
    switch cfg.backoff_type {
    case .Constant:
        duration = backoff_time_constant(cfg)
    case .Linear:
        duration = backoff_time_linear(attempt, cfg)
    case .Exponential:
        duration = backoff_time_exponential(attempt, cfg)
    }
    return
}

run :: proc(
    cfg: ^Config,
    run: proc(_: $Args) -> ($Ret, Status),
    args: Args,
) -> (
    ret: Ret,
    ok: bool,
) {
    status: Status
    for i in 0 ..= cfg.max_retries {
        ret, status = run(args)
        switch status {
        case .Ok:
            ok = true
            return
        case .Fatal:
            ok = false
            return
        case .Fail: // nop
        }
        duration := backoff_time(i, cfg)
        time.sleep(duration)
    }
    return
}

