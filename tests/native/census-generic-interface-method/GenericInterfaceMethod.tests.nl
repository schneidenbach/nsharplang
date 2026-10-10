namespace NSharpLang.CensusGenericInterfaceMethod.Tests

import System
import Microsoft.Extensions.Logging

test "a generic interface method dispatches through the interface it implements" {
    logger := new CapturedLogger()
    sink: ILogger = logger
    assert WriteThrough(sink, LogLevel.Information, "started")
    assert logger.Entries.Count == 1
    assert logger.Entries[0] == "started"
    assert logger.Levels[0] == LogLevel.Information
}

test "the slot's own arguments reach the implementation, exception included" {
    logger := new CapturedLogger()
    sink: ILogger = logger
    WriteFailureThrough(sink, "broke", new InvalidOperationException("why"))
    assert logger.Entries.Count == 1
    assert logger.Entries[0] == "broke/why"
    assert logger.Levels[0] == LogLevel.Error
}

test "the non-generic sibling slot still answers, and gates the generic one" {
    logger := new CapturedLogger()
    sink: ILogger = logger
    assert !WriteThrough(sink, LogLevel.None, "suppressed")
    assert logger.Entries.Count == 0
}

test "the second generic slot on the same interface is filled independently" {
    logger := new CapturedLogger()
    sink: ILogger = logger
    scope := sink.BeginScope<string>("request")
    assert scope == null
    assert logger.Scopes == 1
}

test "the interface map names this class's own generic method for the generic slot" {
    map := typeof(CapturedLogger).GetInterfaceMap(typeof(ILogger))
    logIndex := -1
    index := 0
    while index < map.InterfaceMethods.Length {
        if map.InterfaceMethods[index].Name == "Log" {
            logIndex = index
        }
        index = index + 1
    }
    assert logIndex >= 0
    target := map.TargetMethods[logIndex]
    assert target.DeclaringType == typeof(CapturedLogger)
    assert target.IsGenericMethodDefinition
    assert target.GetGenericArguments().Length == 1
    assert target.IsVirtual
    assert target.IsFinal
}

test "a generic method that matches no slot stays an ordinary non-virtual method" {
    describe := typeof(CapturedLogger).GetMethod("Describe")
    assert describe != null
    assert describe.IsGenericMethodDefinition
    assert !describe.IsVirtual
    logger := new CapturedLogger()
    assert logger.Describe<string>("x") == "0:present"
}
