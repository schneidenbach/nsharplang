using System;
using System.Linq;
using System.Reflection;

namespace NSharpLang.Compiler;

/// <summary>
/// The single enumeration point for "every assembly loaded in this process" used by external-type
/// and doc resolution. Dynamic and collectible assemblies are excluded: they are transient
/// (Reflection.Emit scratch, unloadable AssemblyLoadContexts) and must never win a bare-name lookup
/// against real references. In-process embedders otherwise poison bare BCL names — the test host
/// loads emitted parity assemblies into collectible contexts, and one defining a global type named
/// like a BCL container (`Buffer`, `Math`, ...) intermittently hijacked concurrent in-process
/// compiles' name resolution ("Static method MemoryCopy not found on type Buffer").
/// </summary>
internal static class ExternalAssemblyScan
{
    public static Assembly[] Loaded()
        => AppDomain.CurrentDomain.GetAssemblies()
            .Where(assembly => !assembly.IsDynamic && !assembly.IsCollectible)
            .ToArray();
}
