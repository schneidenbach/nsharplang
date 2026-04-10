using System;
using System.IO;

namespace NSharpLang.Compiler;

public class FormatterConfig
{
    public int IndentSize { get; set; } = 4;
    public bool UseSpaces { get; set; } = true;
    public int MaxLineLength { get; set; } = 100;

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

            if (trimmed.StartsWith("max_line_length"))
            {
                var value = trimmed.Split('=')[1].Trim();
                if (int.TryParse(value, out var maxLen))
                    config.MaxLineLength = maxLen;
            }
        }

        return config;
    }

    private static string? FindEditorConfig(string dir)
    {
        string? current = dir;
        while (current != null)
        {
            var path = Path.Combine(current, ".editorconfig");
            if (File.Exists(path))
                return path;

            current = Path.GetDirectoryName(current);
        }
        return null;
    }

    public string GetIndentString()
    {
        if (UseSpaces)
        {
            return new string(' ', IndentSize);
        }
        else
        {
            return "\t";
        }
    }
}
