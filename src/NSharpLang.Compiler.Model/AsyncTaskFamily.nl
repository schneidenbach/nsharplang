namespace NSharpLang.Compiler

import System


// THE TASK FAMILY AN `async` BODY'S VALUE IS WRAPPED IN WHEN THE DECLARATION DOES NOT NAME ONE.
//
// `async func load(): string` returns a task of `string`; which task is a PROJECT decision, written
// as `language.asyncDefaultType` in `project.yml` and defaulting to `ValueTask`. The analyzer (call
// signatures, hover, `nlc check`) and the columnar emitter (the method's metadata signature) both
// ask this one question, so they cannot disagree about it. Two rules outrank the project default:
//
//   * `main` is always the `Task` family — the CLR's async entry point contract;
//   * an `override`, or an implementation of an interface member, takes the family of the slot it
//     fills, because a .NET slot is matched by its exact return type. That inference lives with each
//     side's own member lookup (`AnalyzerAsyncReturnFamily`, `ColumnarAsyncWrapperSelection`); this
//     file owns only the vocabulary and the project rule.
//
// A declaration that WRITES a task-like return (`: Task<int>`, `: ValueTask`) is never re-wrapped.
enum AsyncTaskFamily {
    ValueTask,
    Task
}

class AsyncTaskFamilyFacts {

    // The project's spelling, already validated by `ProjectFileParser.ValidateConfig` to be one of
    // the two names. Anything else is a caller that skipped validation, and it gets the documented
    // default rather than a guess.
    static func FromConfigName(name: string?): AsyncTaskFamily {
        if string.Equals(name, "Task", StringComparison.Ordinal) {
            return AsyncTaskFamily.Task
        }

        return AsyncTaskFamily.ValueTask
    }

    static func ForLanguage(language: LanguageConfig?): AsyncTaskFamily {
        if language == null {
            return AsyncTaskFamily.ValueTask
        }

        return FromConfigName(language.AsyncDefaultType)
    }

    // The family's source spelling, which is also the CLR simple name of its unit member.
    static func DisplayName(family: AsyncTaskFamily): string {
        if family == AsyncTaskFamily.Task {
            return "Task"
        }

        return "ValueTask"
    }

    // The entry-point rule. Kept exactly as both sides have always spelled it: any function named
    // `main`, in any casing, is the async entry point's shape.
    static func IsEntryPointName(name: string): bool {
        return string.Equals(name, "main", StringComparison.OrdinalIgnoreCase)
    }

    static func EffectiveFamily(functionName: string, projectDefault: AsyncTaskFamily): AsyncTaskFamily {
        if IsEntryPointName(functionName) {
            return AsyncTaskFamily.Task
        }

        return projectDefault
    }
}
