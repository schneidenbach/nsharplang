namespace NSharpLang.Compiler.Performance

record SystemsEffectFacts(Allocates: bool, Boxes: bool, ConstructsDelegate: bool, CapturesClosure: bool, UsesRuntimeDispatch: bool, UsesReflection: bool, UsesDynamicCode: bool, Throws: bool, HasImplicitTrapObligation: bool, UsesUnknownExternalCall: bool, UsesResource: bool, UsesPool: bool, UsesConcurrencyPrimitive: bool, RequiresWarmup: bool, AotSafe: bool) {
}
