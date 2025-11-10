# Task 096: Visual Studio IntelliSense

**Effort:** Large (30-35 hours)
**Depends:** Task 095
**Ships:** Full IntelliSense in Visual Studio

## Goal

Integrate LSP with Visual Studio for IntelliSense.

## Deliverable

VS extension with complete IntelliSense support.

## Implementation

Use Visual Studio Language Server Client:

```csharp
[ContentType("nsharp")]
[Export(typeof(ILanguageClient))]
public class NSharpLanguageClient : ILanguageClient
{
    public string Name => "N# Language Client";

    public IEnumerable<string> ConfigurationSections => null;

    public object InitializationOptions => null;

    public IEnumerable<string> FilesToWatch => null;

    public async Task<Connection> ActivateAsync(
        CancellationToken token)
    {
        var info = new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = GetLanguageServerPath(),
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        var process = Process.Start(info);

        return new Connection(
            process.StandardOutput.BaseStream,
            process.StandardInput.BaseStream);
    }

    public async Task OnLoadedAsync()
    {
        // Register for file events
    }
}
```

## Features

- [ ] Auto-completion (Ctrl+Space)
- [ ] Signature help (Ctrl+Shift+Space)
- [ ] Quick Info (hover)
- [ ] Go to Definition (F12)
- [ ] Find All References (Shift+F12)
- [ ] Rename (Ctrl+R, R)

## Done When

- [ ] IntelliSense works
- [ ] Performance good (<50ms)
- [ ] All features functional
- [ ] Debugger integration works
