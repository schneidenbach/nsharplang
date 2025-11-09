# Task 047: .editorconfig Support

**Effort:** Small (4-5 hours)
**Depends:** Task 046
**Ships:** Formatter respects .editorconfig

## Goal

Read indent settings from .editorconfig.

## Deliverable

Formatter that respects indent_size and indent_style.

## Implementation

Add to `src/Formatter/EditorConfigReader.cs`:

```csharp
public class FormatterConfig
{
    public int IndentSize { get; set; } = 4;
    public bool UseSpaces { get; set; } = true;

    public static FormatterConfig FromEditorConfig(string directory)
    {
        var config = new FormatterConfig();
        var editorConfigPath = FindEditorConfig(directory);

        if (editorConfigPath == null)
            return config;

        var lines = File.ReadAllLines(editorConfigPath);
        bool inNSharpSection = false;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (trimmed.StartsWith("[*.nl]"))
            {
                inNSharpSection = true;
                continue;
            }

            if (trimmed.StartsWith("["))
                inNSharpSection = false;

            if (!inNSharpSection)
                continue;

            if (trimmed.StartsWith("indent_size"))
            {
                var value = trimmed.Split('=')[1].Trim();
                config.IndentSize = int.Parse(value);
            }

            if (trimmed.StartsWith("indent_style"))
            {
                var value = trimmed.Split('=')[1].Trim();
                config.UseSpaces = value == "space";
            }
        }

        return config;
    }

    private static string? FindEditorConfig(string dir)
    {
        while (dir != null)
        {
            var path = Path.Combine(dir, ".editorconfig");
            if (File.Exists(path))
                return path;

            dir = Path.GetDirectoryName(dir);
        }
        return null;
    }
}
```

## Testing

**.editorconfig:**
```ini
[*.nl]
indent_style = space
indent_size = 2
```

```bash
nsharp format Program.nl
# Should use 2-space indent
```

## Done When

- [ ] Reads .editorconfig
- [ ] Respects indent_size
- [ ] Respects indent_style (spaces/tabs)
- [ ] Falls back to defaults if missing
