namespace NSharpLang.StaticRecvRuntime.Inline

import System
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import OmniSharp.Extensions.LanguageServer.Server

class StaticRecvInlineMarker {
}

class SourcePayload {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

class StaticRecvDelegateFacts {
    static func CustomDelegateOrder(): int {
        values: int[] = [1, 3, 2]
        descending: Comparison<int> = (left, right) => right - left
        Array.Sort(values, descending)
        return values[0] * 100 + values[1] * 10 + values[2]
    }

    static func SourceClosedDelegateTotal(): int {
        values: SourcePayload[] = [new SourcePayload(4), new SourcePayload(7)]
        total := 0
        collect: Action<SourcePayload> = payload => {
            total = total + payload.Value
        }
        Array.ForEach(values, collect)
        return total
    }
}

async func main(): Task {
    server := await LanguageServer.From(options => {
        options.WithInput(Console.OpenStandardInput())
        options.WithOutput(Console.OpenStandardOutput())
        options.ConfigureLogging(builder => {
            builder.SetMinimumLevel(LogLevel.Warning)
        })
        options.OnInitialize((server, request, cancellationToken) => {
            return Task.CompletedTask
        })
    })
    await server.WaitForExit
}
