namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Selects the assembly entry point and, for an async top-level main, declares and emits the
// synchronous wrapper the CLR entry-point slot requires. The caller owns assembly persistence; this
// owner returns only the exact MethodBuilder that persistence must publish.
class ColumnarEntryPointRealization {
    static func TryEmit(
        isExecutable: bool,
        funcs: IReadOnlyList<ColumnarFunctionInput>,
        methods: MethodBuilder[],
        asyncWrappedByFunc: Type?[],
        paramTypesByFunc: Dictionary<string, Type>[],
        asyncInnerByFunc: Type[],
        programType: TypeBuilder,
        structRegistry: Dictionary<string, ColumnarStructDef>,
        typeResolutionCatalog: ColumnarSemanticTypeResolutionCatalog,
        out entryPointMethod: MethodBuilder?
    ): bool {
        entryPointMethod = null
        if !isExecutable {
            return true
        }

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

        if mainIndex >= 0 {
            selectedMethod := methods[mainIndex]
            entryPointMethod = selectedMethod
            wrappedReturn := asyncWrappedByFunc[mainIndex]
            if wrappedReturn != null {
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
