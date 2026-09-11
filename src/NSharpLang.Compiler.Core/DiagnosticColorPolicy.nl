namespace NSharpLang.Compiler

import System


// WHEN A COMPILER DIAGNOSTIC IS COLOURED, AND WHY "ALWAYS" IS THE WRONG ANSWER.
//
// `CompilerError.Format` has taken a `useColors` flag since it was written, and both CLI call sites
// passed the default — `true` — so `nlc build` and `nlc run` wrote SGR sequences into a redirected
// stream exactly as readily as into a terminal. That was survivable only because the sequences were
// broken: they arrived as the literal characters `\x1b[...`, which a log reader ignores. Now that
// they carry a real ESC, an unconditional `true` would put escape sequences into every CI log, every
// `2>&1 | grep`, and every file a build is teed into. So the flag needs an owner, and this is it.
//
// THE PRECEDENCE IS THE ONE EVERY OTHER TOOLCHAIN USES, AND THE ORDER IS THE POINT:
//
//   1. an explicit `--color=<when>` on the command line beats everything (it is the only signal the
//      user typed FOR THIS RUN),
//   2. then `NO_COLOR`, because a user who has asked every tool on the machine to stop must not have
//      to ask twice — it wins over `FORCE_COLOR` on purpose,
//   3. then `FORCE_COLOR`, for the CI that renders ANSI in its log viewer and has no terminal,
//   4. and otherwise the stream itself: colour when standard error is a terminal, plain when it is
//      redirected.
//
// `NO_COLOR` follows the published convention (no-color.org): PRESENT AND NON-EMPTY disables. An
// empty value is not a request — it is what an unset variable looks like to a shell that exports it
// anyway — so it is treated as absent. `FORCE_COLOR=0` is likewise read as "off" rather than as
// "present, therefore on", which is what Node's ecosystem established and what a user typing it
// plainly means.
//
// THE DECISION IS A PURE FUNCTION OVER FOUR READINGS, AND THAT IS DELIBERATE. `Decide` takes the
// flag, the two environment values and the redirect state as arguments, so the whole policy is
// crossable from the estate without a process, an environment or a terminal; only
// `ShouldColorizeStandardError` touches the world, and it does nothing but take those four readings.
class DiagnosticColorPolicy {

    // Mode ordinals. Kept as integers rather than an enum because the columnar path reads an enum
    // only through `Convert.ToInt32`, and this is a three-way answer that never leaves the file.
    static func ModeAuto(): int {
        return 0
    }

    static func ModeAlways(): int {
        return 1
    }

    static func ModeNever(): int {
        return 2
    }

    // The one entry point the CLI calls. Every argument to `Decide` is a reading of the world, so
    // this function holds the readings and `Decide` holds the policy.
    static func ShouldColorizeStandardError(): bool {
        return Decide(
            FindColorOption(Environment.GetCommandLineArgs()),
            Environment.GetEnvironmentVariable("NO_COLOR"),
            Environment.GetEnvironmentVariable("FORCE_COLOR"),
            Console.get_IsErrorRedirected()
        )
    }

    // The whole policy, as a function of four readings and nothing else.
    static func Decide(colorOption: string?, noColor: string?, forceColor: string?, isRedirected: bool): bool {
        mode := ParseMode(colorOption)
        if mode == 1 {
            return true
        }

        if mode == 2 {
            return false
        }

        if IsSet(noColor) {
            return false
        }

        if IsSet(forceColor) && forceColor != "0" {
            return true
        }

        return !isRedirected
    }

    // Present and non-empty. An exported-but-empty variable is indistinguishable from an unset one
    // to the user who did not set it, so it must not turn a policy on.
    static func IsSet(value: string?): bool {
        return value != null && value != ""
    }

    // `--color=<when>`, plus the two spellings people actually type: a bare `--color` means "yes"
    // (git's reading) and `--no-color` means "no".
    static func ParseMode(option: string?): int {
        if option == null {
            return 0
        }

        if option == "--no-color" {
            return 2
        }

        if option == "--color" {
            return 1
        }

        if !option.StartsWith("--color=") {
            return 0
        }

        value := option.Substring(8)
        if value == "always" || value == "yes" || value == "force" {
            return 1
        }

        if value == "never" || value == "no" || value == "none" {
            return 2
        }

        // `auto` and anything unrecognised fall through to the stream test rather than failing the
        // build: a colour flag is not worth refusing to compile over.
        return 0
    }

    // The LAST colour flag on the line wins, which is what a shell alias plus an explicit override
    // has to mean.
    static func FindColorOption(args: string[]?): string? {
        if args == null {
            return null
        }

        found: string? = null
        i := 0
        while i < args.Length {
            arg := args[i]
            if IsColorOption(arg) {
                found = arg
            }

            i = i + 1
        }

        return found
    }

    static func IsColorOption(arg: string): bool {
        return arg == "--color" || arg == "--no-color" || arg.StartsWith("--color=")
    }
}
