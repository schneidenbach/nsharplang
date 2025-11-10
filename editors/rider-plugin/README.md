# N# Language Support for JetBrains Rider

This plugin provides basic language support for N# (NewLang Sharp) in JetBrains Rider.

## Features

- **Syntax Highlighting**: Full syntax highlighting for `.nl` files
- **File Recognition**: Automatic detection of N# files and `project.yml` files
- **Project Icons**: Custom icons for N# files and projects in the project view
- **Build Integration**: Build and rebuild N# projects using `dotnet build`
- **Run Configurations**: Run N# projects using `dotnet run`
- **File Templates**: Create new N# files from templates
- **Color Settings**: Customize syntax highlighting colors in IDE preferences

## Installation

### From Source

1. Clone this repository
2. Navigate to the plugin directory:
   ```bash
   cd editors/rider-plugin
   ```
3. Build the plugin:
   ```bash
   ./gradlew buildPlugin
   ```
4. The plugin will be built to `build/distributions/nsharp-rider-plugin-0.1.0.zip`
5. In Rider, go to **Settings → Plugins → Install Plugin from Disk**
6. Select the built zip file

### From JetBrains Marketplace

*Coming soon*

## Usage

### Creating a New N# File

1. Right-click in the project view
2. Select **New → N# File**
3. Enter the file name (extension `.nl` will be added automatically)

### Building a Project

- **Menu**: Build → Build N# Project
- **Keyboard**: Use the standard build shortcuts in Rider

### Running a Project

1. Open any `.nl` file
2. Right-click in the editor
3. Select **Run** to execute the project using `dotnet run`

Or create a run configuration:
1. Go to **Run → Edit Configurations**
2. Click **+** and select **N#**
3. Configure and save

## Requirements

- JetBrains Rider 2024.1 or later
- .NET SDK 8.0 or later
- N# SDK installed (see main project documentation)

## Development

### Building from Source

```bash
./gradlew buildPlugin
```

### Running in Development Mode

```bash
./gradlew runIde
```

This will launch a new instance of Rider with the plugin installed.

### Publishing

```bash
./gradlew publishPlugin
```

Note: Requires `PUBLISH_TOKEN` environment variable set with your JetBrains Marketplace token.

## Project Structure

```
src/main/
├── kotlin/com/nsharp/
│   ├── NSharpLanguage.kt              # Language definition
│   ├── NSharpFileType.kt              # File type definition
│   ├── NSharpParserDefinition.kt      # Parser setup
│   ├── NSharpSyntaxHighlighter.kt     # Syntax highlighting
│   ├── NSharpColorSettingsPage.kt     # Color preferences
│   ├── actions/
│   │   ├── NSharpBuildAction.kt       # Build action
│   │   ├── NSharpRebuildAction.kt     # Rebuild action
│   │   └── NewNSharpFileAction.kt     # New file action
│   ├── icons/
│   │   ├── NSharpIcons.kt             # Icon definitions
│   │   └── NSharpIconProvider.kt      # Icon provider
│   ├── lexer/
│   │   └── NSharpLexer.kt             # Lexical analyzer
│   ├── parser/
│   │   └── NSharpParser.kt            # Parser
│   ├── project/
│   │   └── NSharpProjectViewNodeDecorator.kt  # Project view
│   ├── psi/
│   │   ├── NSharpFile.kt              # PSI file
│   │   └── NSharpTokenTypes.kt        # Token definitions
│   └── run/
│       ├── NSharpConfigurationType.kt        # Run config type
│       ├── NSharpRunConfiguration.kt         # Run config
│       └── NSharpRunConfigurationProducer.kt # Auto-config
└── resources/
    ├── META-INF/
    │   └── plugin.xml                 # Plugin manifest
    ├── icons/
    │   ├── nsharp-file.svg            # File icon
    │   └── nsharp-project.svg         # Project icon
    └── fileTemplates/
        └── NSharp File.nl.ft          # File template
```

## Known Limitations

- **Basic Parser**: The current parser is minimal and doesn't build a full AST
- **No Advanced IntelliSense**: Code completion and navigation require LSP integration (coming in future version)
- **No Debugging**: Debugging support requires additional Rider-specific integration
- **No Refactorings**: Advanced refactorings are not yet implemented

## Future Enhancements

See [Task 091: Rider Plugin (LSP)](../../tasks/091-rider-plugin-lsp.md) for planned improvements:
- Language Server Protocol (LSP) integration
- Advanced IntelliSense features
- Go to definition / Find usages
- Refactoring tools
- Better error detection

## Contributing

Contributions are welcome! Please see the main project [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

See the main project LICENSE file.

## Links

- [N# Project](https://github.com/nsharp-lang/nsharp)
- [N# Documentation](https://nsharp.dev)
- [Report Issues](https://github.com/nsharp-lang/nsharp/issues)
