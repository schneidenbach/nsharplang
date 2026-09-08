namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Collections.Generic
import System.Reflection.Emit

class BuilderBoundValueTupleFirst {
    Name: string

    public constructor(name: string) {
        Name = name
    }
}

class BuilderBoundValueTupleSecond {
    Name: string

    public constructor(name: string) {
        Name = name
    }
}

// These are the three CLR tuple storage shapes used by the emitter's constructor and method job
// queues. Keeping the source classes live while the fixture compiles exercises the same
// TypeBuilder.GetConstructor/GetField rebinding required during the BootstrapServices self-build.
class BuilderBoundValueTupleEmitFacts {
    static func RetainsConstructionAndFields(): bool {
        first := new BuilderBoundValueTupleFirst("first")
        second := new BuilderBoundValueTupleSecond("second")

        parameterTypes := new Type[](1)
        parameterTypes[0] = typeof(string)
        pairJobs := new List<ValueTuple<BuilderBoundValueTupleFirst, Type[]>>()
        pairJobs.Add(new ValueTuple<BuilderBoundValueTupleFirst, Type[]>(first, parameterTypes))
        pair := pairJobs[0]
        if !Object.ReferenceEquals(pair.Item1, first) || !Object.ReferenceEquals(pair.Item2, parameterTypes) {
            return false
        }

        methodOwner := LdftnContinuationEmitFacts.CreateOwner("BuilderBoundValueTupleMethodOwner")
        methodBuilder := LdftnContinuationEmitFacts.DefineMethod(methodOwner, "Work")
        returnType: Type = typeof(string)
        ordinals := new Dictionary<string, int>()
        ordinals["value"] = 17
        methodParameterTypes := new Dictionary<string, Type>()
        methodParameterTypes["value"] = typeof(int)
        interfaceJobs := new List<ValueTuple<BuilderBoundValueTupleFirst, BuilderBoundValueTupleSecond, MethodBuilder, Type, Dictionary<string, int>, Dictionary<string, Type>>>()
        interfaceJobs.Add(new ValueTuple<BuilderBoundValueTupleFirst, BuilderBoundValueTupleSecond, MethodBuilder, Type, Dictionary<string, int>, Dictionary<string, Type>>(first, second, methodBuilder, returnType, ordinals, methodParameterTypes))
        interfaceJob := interfaceJobs[0]
        jobOrdinals := interfaceJob.Item5
        jobParameterTypes := interfaceJob.Item6
        if !Object.ReferenceEquals(interfaceJob.Item1, first) || !Object.ReferenceEquals(interfaceJob.Item2, second) || !Object.ReferenceEquals(interfaceJob.Item3, methodBuilder) || interfaceJob.Item4 != returnType || !Object.ReferenceEquals(jobOrdinals, ordinals) || !Object.ReferenceEquals(jobParameterTypes, methodParameterTypes) {
            return false
        }
        if jobOrdinals == null || jobParameterTypes == null {
            return false
        }
        if jobOrdinals["value"] != 17 || jobParameterTypes["value"] != typeof(int) {
            return false
        }

        rest := new ValueTuple<Dictionary<string, Type>, bool>(methodParameterTypes, true)
        structJobs := new List<ValueTuple<BuilderBoundValueTupleFirst, BuilderBoundValueTupleSecond, MethodBuilder, Type, Type, Type, Dictionary<string, int>, ValueTuple<Dictionary<string, Type>, bool>>>()
        structJobs.Add(new ValueTuple<BuilderBoundValueTupleFirst, BuilderBoundValueTupleSecond, MethodBuilder, Type, Type, Type, Dictionary<string, int>, ValueTuple<Dictionary<string, Type>, bool>>(first, second, methodBuilder, returnType, typeof(int), typeof(string), ordinals, rest))
        structJob := structJobs[0]
        structRest := structJob.Rest
        return Object.ReferenceEquals(structJob.Item1, first) && Object.ReferenceEquals(structJob.Item2, second) && Object.ReferenceEquals(structJob.Item3, methodBuilder) && structJob.Item4 == returnType && structJob.Item5 == typeof(int) && structJob.Item6 == typeof(string) && Object.ReferenceEquals(structJob.Item7, ordinals) && Object.ReferenceEquals(structRest.Item1, methodParameterTypes) && structRest.Item2
    }
}
