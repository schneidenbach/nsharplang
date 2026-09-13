namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Selects the assembly entry point and, for an async top-level main, declares and emits the
// synchronous wrapper the CLR entry-point slot requires. The caller owns assembly persistence; this
// owner returns only the exact MethodBuilder that persistence must publish.
class ColumnarEntryPointRealization {

    // WHICH TOP-LEVEL FUNCTION IS THE ENTRY POINT: `main` anywhere in the program, else `Main`, else
    // none. PUBLISHED because the assembly owner has to resolve the holder type the async wrapper is
    // declared on out of the SAME selection, and two spellings of that walk could disagree.
    static func SelectMainIndex(funcs: IReadOnlyList<ColumnarFunctionInput>): int {
        mainIndex := -1
        f := 0
        while f < funcs.Count && mainIndex < 0 {
            if string.Equals(funcs[f].Name, "main", StringComparison.Ordinal) {
                mainIndex = f
            }
            f += 1
        }
        f = 0
        while f < funcs.Count && mainIndex < 0 {
            if string.Equals(funcs[f].Name, "Main", StringComparison.Ordinal) {
                mainIndex = f
            }
            f += 1
        }
        return mainIndex
    }

    static func TryEmit(
        isExecutable: bool,
        funcs: IReadOnlyList<ColumnarFunctionInput>,
        methods: MethodBuilder[],
        asyncWrappedByFunc: Type?[],
        paramTypesByFunc: Dictionary<string, Type>[],
        asyncInnerByFunc: Type[],
        programType: TypeBuilder?,
        structRegistry: Dictionary<string, ColumnarStructDef>,
        typeResolutionCatalog: ColumnarSemanticTypeResolutionCatalog,
        out entryPointMethod: MethodBuilder?
    ): bool {
        entryPointMethod = null
        if !isExecutable {
            return true
        }

        mainIndex := SelectMainIndex(funcs)

        if mainIndex >= 0 {
            selectedMethod := methods[mainIndex]
            entryPointMethod = selectedMethod
            wrappedReturn := asyncWrappedByFunc[mainIndex]
            if wrappedReturn != null {
                // TOTAL on this path: the caller resolves the holder from the SAME selection this
                // owner makes, so an async `main` always arrives with the type its wrapper belongs on.
                if programType == null {
                    return false
                }
                if paramTypesByFunc[mainIndex].Count != 0 {
                    return false
                }

                innerReturn := asyncInnerByFunc[mainIndex]
                wrapperReturn := ColumnarAsyncEntryPointPlanner.WrapperReturnType(innerReturn)
                noParameters: Type[] = System.Type.EmptyTypes
                wrapper := programType.DefineMethod(
                    "__NSharpEntryPoint",
                    MethodAttributes.Private | MethodAttributes.Static | MethodAttributes.HideBySig,
                    wrapperReturn,
                    noParameters
                )
                plan := ColumnarAsyncEntryPointPlanner.BuildWrapperPlan(
                    selectedMethod,
                    programType,
                    wrappedReturn,
                    innerReturn,
                    typeResolutionCatalog
                )
                wrapperIl := wrapper.GetILGenerator()
                ColumnarCodePlanExecutor.Execute(plan, wrapperIl)
                entryPointMethod = wrapper
            }
        } else {
            enumerator := structRegistry.get_Values().GetEnumerator()
            try {
                while enumerator.MoveNext() {
                    def := enumerator.get_Current()
                    mains: List<ColumnarStaticMethodDef>? = null
                    if def.StaticMethods.TryGetValue("Main", out mains) {
                        if mains == null {
                            throw new NullReferenceException()
                        }
                        if mains.Count == 1 && mains[0].ParamTypes.Length == 0 {
                            entryPointMethod = mains[0].Builder
                            break
                        }
                    }
                }
            } finally {
                enumerator.Dispose()
            }
        }

        if entryPointMethod == null {
            return false
        }
        return true
    }
}
