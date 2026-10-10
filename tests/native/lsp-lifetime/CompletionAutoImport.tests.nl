namespace NSharpLang.LspLifetime.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json

func AutoImportRequest(source: string, typeName: string, namespaceName: string, expected: string, expectImport: bool): string {
    return AutoImportAt(source, typeName, namespaceName, expected, expectImport, -1, "")
}

func AutoImportAt(source: string, typeName: string, namespaceName: string, expected: string, expectImport: bool, caretPosition: int, expectedDiagnosticCode: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-completion-import-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    result := ""
    try {
        File.WriteAllText(Path.Combine(directory, "project.yml"), "name: CompletionImport\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n")
        File.WriteAllText(Path.Combine(directory, "types.nl"), "class Marker { }\n")
        sourcePath := Path.Combine(directory, "Program.nl")
        File.WriteAllText(sourcePath, source)
        partialName := typeName.Substring(0, typeName.Length - 1)
        caret := caretPosition
        if caret < 0 {
            caret = source.LastIndexOf(partialName, StringComparison.Ordinal) + partialName.Length
            assert caret >= partialName.Length
        }
        beforeCaret := source.Substring(0, caret)
        lines := beforeCaret.Split('\n')
        line := lines.Length - 1
        character := lines[line].Length
        uri := "file://" + sourcePath
        request := "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"" + uri + "\",\"languageId\":\"nsharp\",\"version\":1,\"text\":" + AutoImportJsonSource(source) + "}}}"
        File.WriteAllText(Path.Combine(directory, "open.json"), request)
        request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"" + uri + "\"},\"position\":{\"line\":" + line.ToString() + ",\"character\":" + character.ToString() + "}}}"
        File.WriteAllText(Path.Combine(directory, "completion.json"), request)
        script := AutoImportScript(directory)
        run := RunShellScript(script, 60000)
        assert !run.TimedOut, "completion server did not answer before the bound"
        assert run.ExitCode == 0, "completion handshake exited " + run.ExitCode.ToString()
        response := AutoImportResponse(File.ReadAllText(Path.Combine(directory, "out")))
        responseDocument := JsonDocument.Parse(response)
        items := responseDocument.RootElement.GetProperty("result")
        found := false
        itemEnumerator := items.EnumerateArray()
        while itemEnumerator.MoveNext() {
            item := itemEnumerator.Current
            if item.GetProperty("label").GetString() == typeName {
                assert !found, "the matching completion must be unique"
                found = true
                primary := item.GetProperty("textEdit")
                primaryRange := primary.GetProperty("range")
                primaryStart := primaryRange.GetProperty("start")
                primaryEnd := primaryRange.GetProperty("end")
                primaryStartOffset := AutoImportOffset(source, primaryStart.GetProperty("line").GetInt32(), primaryStart.GetProperty("character").GetInt32())
                primaryEndOffset := AutoImportOffset(source, primaryEnd.GetProperty("line").GetInt32(), primaryEnd.GetProperty("character").GetInt32())
                primaryText := primary.GetProperty("newText").GetString() ?? ""
                completed := source.Substring(0, primaryStartOffset) + primaryText + source.Substring(primaryEndOffset)
                combined := primaryText.Contains("import " + namespaceName)
                assert item.GetProperty("insertText").GetString() == typeName
                editCount := 0
                editEnumerator := item.GetProperty("additionalTextEdits").EnumerateArray()
                while editEnumerator.MoveNext() {
                    edit := editEnumerator.Current
                    editCount = editCount + 1
                    range := edit.GetProperty("range")
                    start := range.GetProperty("start")
                    finish := range.GetProperty("end")
                    assert start.GetProperty("line").GetInt32() == finish.GetProperty("line").GetInt32()
                    assert start.GetProperty("character").GetInt32() == finish.GetProperty("character").GetInt32()
                    offset := AutoImportOffset(source, start.GetProperty("line").GetInt32(), start.GetProperty("character").GetInt32())
                    assert offset < primaryStartOffset || offset > primaryEndOffset, "additional edit overlaps the primary word replacement"
                    completed = completed.Substring(0, offset) + edit.GetProperty("newText").GetString() + completed.Substring(offset)
                    assert edit.GetProperty("newText").GetString() == "import " + namespaceName + AutoImportNewline(source)
                }

                detail := item.GetProperty("detail").GetString() ?? ""
                if expectImport {
                    assert editCount == (combined ? 0 : 1)
                    assert detail.Contains("auto-import " + namespaceName)
                } else {
                    assert editCount == 0
                    assert !detail.Contains("auto-import")
                }

                assert completed == expected, completed
                File.WriteAllText(sourcePath, completed)
                if expectedDiagnosticCode.Length == 0 {
                    result = AutoImportCheck(directory)
                } else {
                    AutoImportCheckResult(directory, expectedDiagnosticCode)
                    result = completed
                }
            }
        }

        assert found, "completion did not contain " + typeName + ": " + response
        responseDocument.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }

    return result
}

func AutoImportJsonSource(source: string): string {
    return "\"" + source.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n") + "\""
}

func AutoImportNewline(source: string): string {
    if source.Contains("\r\n") {
        return "\r\n"
    }

    return "\n"
}

func AutoImportOffset(source: string, line: int, character: int): int {
    offset := 0
    currentLine := 0
    while currentLine < line && offset < source.Length {
        if source[offset] == '\n' {
            currentLine = currentLine + 1
        }

        offset = offset + 1
    }

    return offset + character
}

func AutoImportResponse(output: string): string {
    remaining := output
    while remaining.Length > 0 {
        headerEnd := remaining.IndexOf("\r\n\r\n", StringComparison.Ordinal)
        if headerEnd < 0 {
            break
        }

        body := remaining.Substring(headerEnd + 4)
        next := body.IndexOf("Content-Length:", StringComparison.Ordinal)
        remaining = ""
        if next >= 0 {
            remaining = body.Substring(next)
            body = body.Substring(0, next)
        }

        document := JsonDocument.Parse(body)
        propertyEnumerator := document.RootElement.EnumerateObject()
        while propertyEnumerator.MoveNext() {
            property := propertyEnumerator.Current
            if property.Name == "id" && property.Value.GetRawText() == "2" {
                document.Dispose()
                return body
            }
        }

        document.Dispose()
    }

    throw new InvalidOperationException("The completion response was absent: " + output)
}

func AutoImportCheck(directory: string): string {
    return AutoImportCheckResult(directory, "")
}

func AutoImportCheckResult(directory: string, expectedDiagnosticCode: string): string {
    cli := Path.Combine(LspRepositoryRoot(), "src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll")
    startInfo := new ProcessStartInfo("dotnet", "\"" + cli + "\" check --project \"" + directory + "\" --json")
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    process := new Process { StartInfo: startInfo }
    process.Start()
    output := process.StandardOutput.ReadToEnd()
    errorText := process.StandardError.ReadToEnd()
    process.WaitForExit()
    exitCode := process.ExitCode
    process.Dispose()
    assert exitCode == (expectedDiagnosticCode.Length == 0 ? 0 : 1), output + errorText
    if expectedDiagnosticCode.Length > 0 {
        assert output.Contains("\"code\": \"" + expectedDiagnosticCode + "\""), output
    }

    return output
}

func AutoImportScript(directory: string): string {
    template := """
exec > /dev/null 2>&1
d="@DIRECTORY@"
mkfifo "$d/in" || exit 91
dotnet "@DLL@" --stdio < "$d/in" > "$d/out" 2>"$d/err" &
server=$!
trap 'kill "$server" 2>/dev/null; wait "$server" 2>/dev/null' EXIT
exec 3> "$d/in"
send() { m=$1; printf 'Content-Length: %d\r\n\r\n%s' "${#m}" "$m" >&3; }
send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":"file://@DIRECTORY@","capabilities":{}}}'
waited=0
while ! grep -q '"id":1' "$d/out" && [ "$waited" -lt 30 ]; do sleep 1; waited=$((waited + 1)); done
grep -q '"id":1' "$d/out" || exit 92
send '{"jsonrpc":"2.0","method":"initialized","params":{}}'
send "$(cat "$d/open.json")"
send "$(cat "$d/completion.json")"
waited=0
while ! grep -q '"id":2' "$d/out" && [ "$waited" -lt 30 ]; do sleep 1; waited=$((waited + 1)); done
grep -q '"id":2' "$d/out" || exit 93
send '{"jsonrpc":"2.0","method":"exit","params":null}'
wait "$server"
rc=$?
exec 3>&-
exit "$rc"
"""
    return template.Replace("@DIRECTORY@", directory).Replace("@DLL@", LanguageServerDll())
}

test "completion auto-import: accepting a package type inserts its namespace and the completed source checks" {
    if IsUnix() {
        source := "func Create(): DeserializerBuilder { return new DeserializerBuilde() }\n"
        expected := "import YamlDotNet.Serialization\nfunc Create(): DeserializerBuilder { return new DeserializerBuilder() }\n"
        assert AutoImportRequest(source, "DeserializerBuilder", "YamlDotNet.Serialization", expected, true).Contains("\"ok\": true")
    }
}

test "completion auto-import: existing imports and current namespace or package require no edit" {
    if IsUnix() {
        source := "import System.Text\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", source.Replace("StringBuilde()", "StringBuilder()"), false).Contains("\"ok\": true")
        source = "namespace System.Text\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", source.Replace("StringBuilde()", "StringBuilder()"), false).Contains("\"ok\": true")
        source = "package System.Text\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", source.Replace("StringBuilde()", "StringBuilder()"), false).Contains("\"ok\": true")
    }
}

test "completion auto-import: namespace package and file-import headers keep their order" {
    if IsUnix() {
        source := "namespace Example\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        expected := "namespace Example\nimport System.Text\nfunc Create(): StringBuilder { return new StringBuilder() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", expected, true).Contains("\"ok\": true")
        source = "package Example\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        expected = "package Example\nimport System.Text\nfunc Create(): StringBuilder { return new StringBuilder() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", expected, true).Contains("\"ok\": true")
        source = "import \"./types.nl\"\nfunc MarkerValue(): Marker { return new Marker() }\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        expected = "import \"./types.nl\"\nimport System.Text\nfunc MarkerValue(): Marker { return new Marker() }\nfunc Create(): StringBuilder { return new StringBuilder() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", expected, true).Contains("\"ok\": true")
    }
}

test "completion auto-import: a CRLF document receives a CRLF import edit" {
    if IsUnix() {
        source := "namespace Example\r\nfunc Create(): StringBuilder { return new StringBuilde() }\r\n"
        expected := "namespace Example\r\nimport System.Text\r\nfunc Create(): StringBuilder { return new StringBuilder() }\r\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", expected, true).Contains("\"ok\": true")
    }
}

test "completion auto-import: multiline directive names and trailing comments stay intact" {
    if IsUnix() {
        source := "namespace Example /* header\ncomment */\n/// Factory docs\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        expected := "namespace Example /* header\ncomment */\nimport System.Text\n/// Factory docs\nfunc Create(): StringBuilder { return new StringBuilder() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", expected, true).Contains("\"ok\": true")
        source = "namespace Example.\nNested\nfunc Create(): StringBuilder { return new StringBuilde() }\n"
        expected = "namespace Example.\nNested\nimport System.Text\nfunc Create(): StringBuilder { return new StringBuilder() }\n"
        assert AutoImportRequest(source, "StringBuilder", "System.Text", expected, true).Contains("\"ok\": true")
    }
}

test "completion auto-import: start-of-file and empty-file edits combine without overlap" {
    if IsUnix() {
        source := "StringBuilde"
        expected := "import System.Text\nStringBuilder"
        assert AutoImportAt(source, "StringBuilder", "System.Text", expected, true, 12, "NL101") == expected
        expected = "import System\nConsole"
        assert AutoImportAt("", "Console", "System", expected, true, 0, "NL101") == expected
        source = "namespace StringBuilde"
        expected = "namespace StringBuilder\nimport System.Text\n"
        assert AutoImportAt(source, "StringBuilder", "System.Text", expected, true, source.Length, "NL010") == expected
    }
}

test "completion auto-import: the whole identifier is replaced when the caret precedes its suffix" {
    if IsUnix() {
        source := "func Create(): StringBuilder { return new StringBuildeWrong() }\n"
        expected := "import System.Text\nfunc Create(): StringBuilder { return new StringBuilder() }\n"
        caret := source.IndexOf("Wrong", StringComparison.Ordinal)
        assert AutoImportAt(source, "StringBuilder", "System.Text", expected, true, caret, "").Contains("\"ok\": true")
    }
}

test "completion auto-import: incomplete syntax still receives a bounded usable edit" {
    if IsUnix() {
        source := "namespace Example\nfunc Create(): StringBuilder { return new StringBuilde("
        expected := "namespace Example\nimport System.Text\nfunc Create(): StringBuilder { return new StringBuilder("
        assert AutoImportAt(source, "StringBuilder", "System.Text", expected, true, -1, "NL107") == expected
    }
}
