using System;
using System.Threading.Tasks;
using LanguageServer.Handlers;
using LanguageServer.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Server;

namespace LanguageServer;

class Program
{
    static async Task Main(string[] args)
    {
        // Setup logging
        var logPath = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nsharp",
            "lsp.log"
        );

        System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(logPath)!);

        Console.Error.WriteLine($"N# Language Server starting... (log: {logPath})");

        try
        {
            var server = await OmniSharp.Extensions.LanguageServer.Server.LanguageServer.From(options =>
                options
                    .WithInput(Console.OpenStandardInput())
                    .WithOutput(Console.OpenStandardOutput())
                    .ConfigureLogging(builder =>
                    {
                        builder
                            .AddFile(logPath)
                            .SetMinimumLevel(LogLevel.Debug);
                    })
                    .WithServices(services =>
                    {
                        services.AddSingleton<DocumentManager>();
                    })
                    .WithHandler<TextDocumentHandler>()
                    .WithHandler<CompletionHandler>()
                    .WithHandler<HoverHandler>()
                    .OnInitialize(async (server, request, cancellationToken) =>
                    {
                        var logger = server.Services.GetRequiredService<ILogger<Program>>();
                        logger.LogInformation("N# Language Server initialized");
                        logger.LogInformation("Client: {ClientName} {ClientVersion}",
                            request.ClientInfo?.Name,
                            request.ClientInfo?.Version);
                    })
            );

            Console.Error.WriteLine("N# Language Server initialized successfully");

            await server.WaitForExit;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Fatal error in Language Server: {ex}");
            throw;
        }
    }
}
