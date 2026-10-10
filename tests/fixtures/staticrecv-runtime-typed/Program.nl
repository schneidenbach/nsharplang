namespace NSharpLang.StaticRecvRuntime.Typed

import System
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import OmniSharp.Extensions.LanguageServer.Server

class StaticRecvTypedMarker {
}

async func main(): Task {
    configure: Action<LanguageServerOptions> = options => {
        options.WithInput(Console.OpenStandardInput())
        options.WithOutput(Console.OpenStandardOutput())
        options.ConfigureLogging(builder => {
            builder.SetMinimumLevel(LogLevel.Warning)
        })
        options.OnInitialize((server, request, cancellationToken) => {
            return Task.CompletedTask
        })
    }
    server := await LanguageServer.From(configure)
    await server.WaitForExit
}
