namespace NSharpLang.Compiler.Ast

import System.Collections.Generic

public class TypeParameter {
    Name: string

    constructor(Name: string) {
        this.Name = Name
    }
}

public class GenericConstraint {
    TypeParameter: string
    Constraints: List<TypeReference>
    SpecialConstraints: SpecialConstraintKind

    constructor(typeParameter: string, constraints: List<TypeReference>, specialConstraints: SpecialConstraintKind = 0) {
        TypeParameter = typeParameter
        Constraints = constraints
        SpecialConstraints = specialConstraints
    }
}
