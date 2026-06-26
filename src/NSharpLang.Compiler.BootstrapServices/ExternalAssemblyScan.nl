namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

public class ExternalAssemblyScan {
    public static func Loaded(): Assembly[] {
        assemblies := AppDomain.CurrentDomain.GetAssemblies()
        loaded := new List<Assembly>()

        i := 0
        while i < assemblies.Length {
            assembly := assemblies[i]
            if !assembly.IsDynamic && !assembly.IsCollectible {
                loaded.Add(assembly)
            }

            i = i + 1
        }

        return loaded.ToArray()
    }
}
