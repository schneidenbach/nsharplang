namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

public class ColumnarSourceFile {
    FileName: string
    Source: string
    FileId: int
    LineStarts: int[]

    constructor(fileName: string, source: string, fileId: int, lineStarts: int[]) {
        FileName = fileName
        Source = source
        FileId = fileId
        LineStarts = lineStarts
    }
}

public class ColumnarEmissionPlanner {
    public static func BuildSourceFiles(sources: string[], fileNames: string[]): ColumnarSourceFile[] {
        if sources.Length != fileNames.Length {
            throw new ArgumentException("Columnar source and file-name arrays must have the same length.")
        }

        files := new ColumnarSourceFile[](sources.Length)
        index := 0
        while index < sources.Length {
            files[index] = new ColumnarSourceFile(
                fileNames[index],
                sources[index],
                index,
                BuildLineStarts(sources[index]))
            index = index + 1
        }

        return files
    }

    public static func IsExecutableOutput(outputType: string?): bool {
        return string.Equals(outputType ?? "", "exe", StringComparison.OrdinalIgnoreCase)
    }

    public static func IsEnabledEnvironmentFlag(value: string?): bool {
        return string.Equals(value ?? "", "1", StringComparison.Ordinal)
            || string.Equals(value ?? "", "true", StringComparison.OrdinalIgnoreCase)
    }

    static func BuildLineStarts(source: string): int[] {
        starts := new List<int>()
        starts.Add(0)

        index := 0
        while index < source.Length {
            if source[index] == '\r' {
                if index + 1 < source.Length && source[index + 1] == '\n' {
                    starts.Add(index + 2)
                    index = index + 2
                } else {
                    starts.Add(index + 1)
                    index = index + 1
                }
            } else if source[index] == '\n' {
                starts.Add(index + 1)
                index = index + 1
            } else {
                index = index + 1
            }
        }

        return starts.ToArray()
    }
}
