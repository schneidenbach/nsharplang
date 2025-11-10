# Rider Plugin Development Setup

This guide explains how to set up the development environment for the N# Rider plugin.

## Prerequisites

- JDK 17 or later
- IntelliJ IDEA (Community or Ultimate) or JetBrains Rider
- Gradle 8.5+ (included via wrapper)

## Setup Steps

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/nsharp.git
cd nsharp/editors/rider-plugin
```

### 2. Build the Plugin

```bash
./gradlew buildPlugin
```

This will:
- Download all dependencies
- Compile the Kotlin code
- Generate the plugin JAR
- Create a distributable ZIP in `build/distributions/`

### 3. Run in Development Mode

To test the plugin in a sandboxed Rider instance:

```bash
./gradlew runIde
```

This launches a new Rider window with the plugin installed. Any changes to `.nl` files will show syntax highlighting.

### 4. Install Locally

To install the plugin in your actual Rider installation:

1. Build the plugin: `./gradlew buildPlugin`
2. Open Rider
3. Go to **Settings → Plugins**
4. Click the gear icon and select **Install Plugin from Disk...**
5. Navigate to `build/distributions/nsharp-rider-plugin-0.1.0.zip`
6. Click OK and restart Rider

## Development Workflow

### Making Changes

1. Edit the Kotlin source files in `src/main/kotlin/`
2. Run `./gradlew buildPlugin` to verify compilation
3. Run `./gradlew runIde` to test in a sandbox
4. Iterate

### Testing Syntax Highlighting

1. In the sandbox Rider, create a test project
2. Add a file with `.nl` extension
3. Enter N# code and verify highlighting

Example test code:
```nsharp
import System

func main() {
    name := "N#"
    Console.WriteLine("Hello from " + name)
}

type Person = record {
    Name: string
    Age: int
}

union Result<T> {
    | Success(T)
    | Error(string)
}
```

### Testing Build Integration

1. Create or open an N# project with a `project.yml` file
2. Use **Build → Build N# Project** from the menu
3. Verify the build output appears in the Build tool window

### Testing Run Configurations

1. Right-click a `.nl` file
2. Select **Run** to create and execute a run configuration
3. Verify `dotnet run` executes correctly

## Project Structure

```
editors/rider-plugin/
├── src/main/
│   ├── kotlin/com/nsharp/     # Plugin source code
│   └── resources/              # Resources (icons, templates, plugin.xml)
├── build.gradle.kts            # Gradle build configuration
├── settings.gradle.kts         # Gradle settings
├── gradle.properties           # Gradle properties
└── README.md                   # User documentation
```

## Common Tasks

### Clean Build

```bash
./gradlew clean buildPlugin
```

### Verify Plugin

```bash
./gradlew verifyPlugin
```

This checks for common plugin issues.

### Run Tests

```bash
./gradlew test
```

(Note: No tests implemented yet in v0.1.0)

## Debugging

### Enable Debug Logging

1. Run with debug output:
   ```bash
   ./gradlew runIde --debug
   ```

2. In the sandbox IDE, check **Help → Show Log in Finder/Explorer**

### Common Issues

**Issue**: "Unsupported class file version"
- **Solution**: Ensure you're using JDK 17 or later

**Issue**: "Plugin is not compatible with this version of Rider"
- **Solution**: Check `sinceBuild` and `untilBuild` in `build.gradle.kts`

**Issue**: Icons not showing
- **Solution**: Verify SVG files are in `src/main/resources/icons/`

## Publishing

### Build for Distribution

```bash
./gradlew clean buildPlugin
```

The distributable ZIP will be in:
```
build/distributions/nsharp-rider-plugin-0.1.0.zip
```

### Publish to JetBrains Marketplace

1. Create a JetBrains account at https://plugins.jetbrains.com/
2. Get your publish token
3. Set environment variable:
   ```bash
   export PUBLISH_TOKEN=your-token-here
   ```
4. Publish:
   ```bash
   ./gradlew publishPlugin
   ```

## Resources

- [IntelliJ Platform SDK Documentation](https://plugins.jetbrains.com/docs/intellij/welcome.html)
- [Rider Plugin Development](https://www.jetbrains.com/help/rider/Plugins.html)
- [Gradle IntelliJ Plugin](https://github.com/JetBrains/gradle-intellij-plugin)

## Support

For issues or questions:
- File an issue: https://github.com/nsharp-lang/nsharp/issues
- Main project docs: https://nsharp.dev
