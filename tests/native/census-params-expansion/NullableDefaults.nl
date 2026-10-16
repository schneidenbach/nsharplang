namespace NSharpLang.CensusParamsExpansion.Tests

import System.Reflection
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.Columnar


// A `Nullable<T>` OPTIONAL DEFAULT THAT HAS A VALUE. `Serilog.Extensions.Logging.File`'s `AddFile`
// is the shape that needed it: its tail carries `long? fileSizeLimitBytes = 1073741824` and
// `int? retainedFileCountLimit = 31`, and while such a parameter was unfillable the whole overload
// was refused at EVERY arity — so `builder.AddFile(logPath)`, which the language server's host
// bootstrap writes, could not bind at all. The metadata constant is the UNDERLYING one, so the call
// site pushes that literal and wraps it with `newobj Nullable<T>::.ctor(T)`.

// THE CALL ITSELF, COMPILED: one written argument for a declaration whose omitted tail includes
// both of those nullables, so this body emitting at all is the regression, and the IL-verification
// sweep reads the wrap it writes. It is not executed here because `ILoggingBuilder` cannot be
// IMPLEMENTED in N# today — an external interface with a property declines at emission — so no body
// can hand it a receiver.
func ConfigureFileLogging(builder: ILoggingBuilder, logPath: string) {
    builder.AddFile(logPath)
    builder.SetMinimumLevel(LogLevel.Debug)
}

// The same declaration, read off the REAL reflected metadata rather than off a fixture that merely
// resembles it: the widest `AddFile` whose receiver slot is `ILoggingBuilder`.
func AddFileBuilderParameters(): ParameterInfo[] {
    assembly := Assembly.Load("Serilog.Extensions.Logging.File")
    host := assembly.GetType("Microsoft.Extensions.Logging.FileLoggerExtensions")
    if host == null {
        return new ParameterInfo[](0)
    }

    widest := new ParameterInfo[](0)
    for candidate in host.GetMethods() {
        if candidate.Name == "AddFile" {
            parameters := candidate.GetParameters()
            if parameters.Length > widest.Length && parameters[0].ParameterType.Name == "ILoggingBuilder" {
                widest = parameters
            }
        }
    }

    return widest
}

// Every OPTIONAL parameter of that declaration, rendered as the value its omitted argument is
// filled with — `null`, or `<constant type>=<constant>` — so one row reads the whole tail and a
// change anywhere in it is visible. A `Nullable<T>` with a value renders as its `T` constant, which
// is what the call site pushes before the wrap.
func AddFileOptionalTail(): string {
    rendered := ""
    for parameter in AddFileBuilderParameters() {
        if parameter.IsOptional {
            value := ColumnarParameterDefaultValue.FromMetadata(parameter, parameter.ParameterType)
            text := "<unfillable>"
            if value != null {
                if value.Form == ColumnarParameterDefaultValue.NullReferenceForm {
                    text = "null"
                } else if value.Form == ColumnarParameterDefaultValue.ZeroValueForm {
                    text = "zero"
                } else {
                    constant := value.Constant
                    if constant != null {
                        text = constant.GetType().Name + "=" + (constant.ToString() ?? "")
                    }
                }
            }

            if rendered.Length > 0 {
                rendered = rendered + " "
            }

            rendered = rendered + text
        }
    }

    return rendered
}
