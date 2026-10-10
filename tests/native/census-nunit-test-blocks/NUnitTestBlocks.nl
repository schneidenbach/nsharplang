namespace NSharpLang.CensusNUnitTestBlocks.Tests

import System
import System.Collections.Generic
import System.Reflection

// THE PROJECT EXISTS FOR ITS `project.yml`: `testFramework: nunit` plus `test` blocks. Everything
// the framework choice reaches — the attribute types the lowering binds, the reference set the
// restore writes, and the runner `nlc test` picks — is exercised by building and running this
// project at all. The subject under test is therefore small on purpose.
func Add(a: int, b: int): int => a + b

func Describe(value: int): string {
    if value < 0 {
        return "negative"
    }
    if value == 0 {
        return "zero"
    }
    return "positive"
}

// The lowered test type, read back out of the running assembly. A test that asks what the EMITTER
// wrote has to find the emitter's own output, and the type name is the lowering's contract: the rows
// are written in `NUnitTestBlocks.tests.nl` under `NSharpLang.CensusNUnitTestBlocks.Tests`, so they
// land on `NSharpLang.CensusNUnitTestBlocks.Tests.NUnitTestBlocksTests` — the file's own namespace,
// which is the one its bodies already bind their bare names through.
func RequiredTestMethod(name: string): MethodInfo {
    loweredTestTypeName := "NSharpLang.CensusNUnitTestBlocks.Tests.NUnitTestBlocksTests"
    testType := Type.GetType(loweredTestTypeName)
    if testType == null {
        throw new InvalidOperationException("The lowered '" + loweredTestTypeName + "' type was not found in this assembly.")
    }
    method := testType.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("The lowered test method '" + name + "' was not found.")
    }
    return method
}

func AttributeNames(method: MethodInfo): List<string> {
    names := new List<string>()
    for attribute in method.GetCustomAttributesData() {
        names.Add(attribute.AttributeType.FullName ?? "")
    }
    return names
}

func ListContains(values: List<string>, candidate: string): bool {
    for value in values {
        if value == candidate {
            return true
        }
    }
    return false
}
