# Task 091: Rider LSP Integration

**Effort:** Medium (12-15 hours)
**Depends:** Task 090
**Ships:** IntelliSense works in Rider

## Goal

Integrate N# language server with Rider.

## Deliverable

Rider plugin that uses LSP for IntelliSense.

## Implementation

```kotlin
class NSharpLanguageServer : ProcessHandlerLspServerSupportProvider() {
    override fun createCommandLine(project: Project): GeneralCommandLine {
        val serverPath = findLanguageServer()
        return GeneralCommandLine()
            .withExePath("dotnet")
            .withParameters(serverPath)
            .withCharset(Charsets.UTF_8)
    }

    private fun findLanguageServer(): String {
        // Look for bundled server or installed SDK
        val bundled = File(PathManager.getPluginsPath(),
            "nsharp/server/LanguageServer.dll")
        if (bundled.exists())
            return bundled.absolutePath

        // Fall back to SDK installation
        return "LanguageServer.dll"
    }
}
```

## Features

- [ ] Auto-completion
- [ ] Signature help
- [ ] Hover documentation
- [ ] Go to definition
- [ ] Find references

## Done When

- [ ] IntelliSense works
- [ ] Performance acceptable (<100ms)
- [ ] Error squiggles show
- [ ] Works with LSP from Task 037
