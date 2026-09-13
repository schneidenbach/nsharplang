namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE LINTER: THE PUBLIC ENTRY THE CLI AND THE EDITOR CALL, AND THE DECLARATION WALK IT DRIVES.
//
// This file closes `Linter.cs`. The three slices before it took the per-file state, the reporting
// spine and the function/statement/expression arms; what was left was the DECLARATION walk, the
// `Visit` that enters it, and the public `Linter` those two exist to serve. The escape analysis says
// that remainder is one closed cut — the declaration territory escapes to nothing, adding `Visit`
// escapes to nothing, and adding `Lint` escapes only to the visitor's own constructor — so there is
// no smaller honest slice and no reason to leave a host behind.
//
// THE FILE WAS DELETED RATHER THAN REDUCED, AND THAT IS A MEASURED CHOICE. Every type in `Linter`'s
// public signature was ALREADY N#: `CompilationUnit`, `Diagnostic` and `LinterConfig` all live in this
// assembly, in this namespace. So the owner can carry the same namespace and the same name, and the
// six production consumers — the `lint` command, the language server's `DocumentManager`, the
// playground, `MultiFileCompiler`, `FixApplicator` and `CodeIntelligenceService` — plus every C# test
// bind to it with no source change at all. A reviewed zero-policy host would have been the weaker arm
// of the same slice; nothing about the seam required it.
//
// THE `Action` THAT MADE `VisitWithTypeMemberScope` LOOK IMMOVABLE IS GONE, AND IT WAS NEVER A
// LANGUAGE BOUNDARY. The C# extracted a bracket its three type arms shared and passed the loop in as a
// callback, which is why the previous slice marked it for reviewed-mechanical. Once the three callers
// are themselves N# the callback has nothing to carry: each writes its own `try`/`finally` around its
// own loop, and the shared bracket ceases to exist. What is written out three times below is the
// whole of what the callback did.

// THE DECLARATION WALK. One arm per declaration shape, in the order the C# `switch` tested them, and
// a shape with no arm is walked no further. The AST's declaration hierarchy is FLAT — every one of the
// nineteen declaration types derives directly from `Declaration` — so the order is not load-bearing;
// it is preserved anyway, because a reader comparing this against the deleted `switch` should not have
// to prove that for themselves.
//
// THE EMPTY ARMS ARE REPRODUCED RATHER THAN DROPPED. A union and an enum declaration matched a case
// that did nothing, and they still match one here. Deleting them would say the same thing to the
// machine and something weaker to a reader: that nobody had decided, rather than that a union carries
// no expression, no binding and no nested body the linter needs to see.
class LinterDeclarationWalk {
    state: LinterWalkState
    walk: LinterWalk

    constructor(walkState: LinterWalkState) {
        state = walkState
        walk = new LinterWalk(walkState)
    }

    // The whole of one file. The imports are registered BEFORE any declaration is walked, because
    // NL002 and NL010 both need the import table complete while the body is being read; the unused
    // imports are checked AFTER, because that answer needs every identifier in the file.
    func Visit(unit: CompilationUnit) {
        state.RegisterImports(unit)

        state.PushScope()

        for declaration in unit.Declarations {
            VisitDeclaration(declaration)
        }

        state.CheckUnusedVariables()
        state.PopScope()

        // THE TWO IMPORT RULES ARE ONE MEASUREMENT READ FROM TWO SIDES, so they run together, after
        // the walk, over the same facts: an import that supplied a name is USED (NL010 quiet), and a
        // name whose supplying namespace is not imported is MISSING one (NL002 speaks).
        state.CheckUnusedImports()
        state.CheckMissingImports()
    }

    // EVERY ATTRIBUTE ON A DECLARATION NAMES A TYPE, AND EVERY ARGUMENT IS AN EXPRESSION. Neither was
    // read: `[Obsolete("old")]` on a function in a file whose only other mention of `System` was that
    // attribute made NL010 report the import dead, and `nlc fix` offered to delete it. Both halves are
    // tracked at ONE place, so a declaration kind that grows attributes cannot get half of it.
    func TrackAttributes(attributes: List<AttributeNode>?) {
        if attributes == null {
            return
        }

        for attribute in attributes {
            state.NoteAttributeName(attribute.Name)
            for argument in attribute.Arguments {
                walk.VisitExpression(argument.Value)
            }
        }
    }

    func VisitDeclaration(declaration: Declaration) {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            TrackAttributes(functionDeclaration.Attributes)
            walk.VisitFunction(functionDeclaration)
            return
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            TrackAttributes(classDeclaration.Attributes)
            // NL010: a base class and every implemented interface are used type names.
            state.TrackTypeReference(classDeclaration.BaseClass)
            for interfaceReference in classDeclaration.Interfaces {
                state.TrackTypeReference(interfaceReference)
            }

            VisitClass(classDeclaration)
            return
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            TrackAttributes(structDeclaration.Attributes)
            for interfaceReference in structDeclaration.Interfaces {
                state.TrackTypeReference(interfaceReference)
            }

            VisitStruct(structDeclaration)
            return
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            TrackAttributes(recordDeclaration.Attributes)
            for interfaceReference in recordDeclaration.Interfaces {
                state.TrackTypeReference(interfaceReference)
            }

            VisitRecord(recordDeclaration)
            return
        }

        // A struct-of-arrays record's columns are type references and nothing else: there are no
        // members to walk, so the arm tracks the types and stops.
        soaRecordDeclaration := declaration as SoaRecordDeclaration
        if soaRecordDeclaration != null {
            for columnDeclaration in soaRecordDeclaration.Columns {
                state.TrackTypeReference(columnDeclaration.Type)
            }

            return
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            TrackAttributes(interfaceDeclaration.Attributes)
            for interfaceReference in interfaceDeclaration.BaseInterfaces {
                state.TrackTypeReference(interfaceReference)
            }

            VisitInterface(interfaceDeclaration)
            return
        }

        // A UNION'S CASES ARE WRITTEN TYPES. `union Outcome { Ok(StringBuilder) | Err(string) }` was
        // walked no further than its name, so a file whose only mention of an import was a union case
        // payload had that import reported dead. There is still nothing else to walk — a case has no
        // body and no initializer — so the arm tracks the payload types and stops.
        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            TrackAttributes(unionDeclaration.Attributes)
            for unionCase in unionDeclaration.Cases {
                properties := unionCase.Properties
                if properties != null {
                    for caseProperty in properties {
                        state.TrackTypeReference(caseProperty.Type)
                    }
                }
            }

            return
        }

        // An enum's members are names and constant values; only its attributes name a type.
        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            TrackAttributes(enumDeclaration.Attributes)
            return
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            TrackAttributes(fieldDeclaration.Attributes)
            state.TrackTypeReference(fieldDeclaration.Type)
            initializer := fieldDeclaration.Initializer
            if initializer != null {
                walk.VisitExpression(initializer)
            }

            return
        }

        // An event names exactly one type — its handler delegate — and carries no body at all, so the
        // import that supplies that delegate is USED by the declaration alone.
        eventDeclaration := declaration as EventDeclaration
        if eventDeclaration != null {
            TrackAttributes(eventDeclaration.Attributes)
            state.TrackTypeReference(eventDeclaration.Type)
            return
        }

        // A property's three bodies are independent: an expression body, a getter and a setter may all
        // be present, and each is walked on its own terms rather than as alternatives.
        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            TrackAttributes(propertyDeclaration.Attributes)
            state.TrackTypeReference(propertyDeclaration.Type)
            expressionBody := propertyDeclaration.ExpressionBody
            if expressionBody != null {
                walk.VisitExpression(expressionBody)
            }

            getBody := propertyDeclaration.GetBody
            if getBody != null {
                walk.VisitStatement(getBody)
            }

            setBody := propertyDeclaration.SetBody
            if setBody != null {
                walk.VisitStatement(setBody)
            }

            return
        }

        constructorDeclaration := declaration as ConstructorDeclaration
        if constructorDeclaration != null {
            TrackAttributes(constructorDeclaration.Attributes)
            for constructorParameter in constructorDeclaration.Parameters {
                TrackAttributes(constructorParameter.Attributes)
                state.TrackTypeReference(constructorParameter.Type)
            }

            initializer := constructorDeclaration.Initializer
            if initializer != null {
                walk.VisitExpression(initializer)
            }

            walk.VisitStatement(constructorDeclaration.Body)
            return
        }

        // AN INDEXER, A TYPE ALIAS AND A NEWTYPE WERE NOT MATCHED AT ALL, so every type they write —
        // an element type, an alias target, a wrapped type — was invisible to both import rules.
        indexerDeclaration := declaration as IndexerDeclaration
        if indexerDeclaration != null {
            TrackAttributes(indexerDeclaration.Attributes)
            state.TrackTypeReference(indexerDeclaration.Type)
            for indexerParameter in indexerDeclaration.Parameters {
                TrackAttributes(indexerParameter.Attributes)
                state.TrackTypeReference(indexerParameter.Type)
            }

            indexerGetBody := indexerDeclaration.GetBody
            if indexerGetBody != null {
                walk.VisitStatement(indexerGetBody)
            }

            indexerSetBody := indexerDeclaration.SetBody
            if indexerSetBody != null {
                walk.VisitStatement(indexerSetBody)
            }

            return
        }

        typeAliasDeclaration := declaration as TypeAliasDeclaration
        if typeAliasDeclaration != null {
            state.TrackTypeReference(typeAliasDeclaration.Type)
            return
        }

        newtypeDeclaration := declaration as NewtypeDeclaration
        if newtypeDeclaration != null {
            state.TrackTypeReference(newtypeDeclaration.UnderlyingType)
            return
        }

        // A table test's cases are expressions in the DECLARATION's own scope, walked before the body,
        // and its table parameters are type references the file uses.
        testDeclaration := declaration as TestDeclaration
        if testDeclaration != null {
            tableParameters := testDeclaration.TableParameters
            if tableParameters != null {
                for parameter in tableParameters {
                    state.TrackTypeReference(parameter.Type)
                }
            }

            tableCases := testDeclaration.TableCases
            if tableCases != null {
                for row in tableCases {
                    for caseExpression in row {
                        walk.VisitExpression(caseExpression)
                    }
                }
            }

            walk.VisitStatement(testDeclaration.Body)
            return
        }

        setupDeclaration := declaration as SetupDeclaration
        if setupDeclaration != null {
            walk.VisitStatement(setupDeclaration.Body)
            return
        }

        teardownDeclaration := declaration as TeardownDeclaration
        if teardownDeclaration != null {
            walk.VisitStatement(teardownDeclaration.Body)
            return
        }
    }

    // A type's members are walked inside a scope that knows every member NAME and every primary
    // constructor parameter, so NL002 does not report a field read as a missing import. The scope is
    // popped in a `finally`, because a throw part-way through a member must not leave the next type's
    // members reading this one's names.
    func VisitClass(classDeclaration: ClassDeclaration) {
        members := classDeclaration.Members
        state.PushTypeMemberScope(members, classDeclaration.PrimaryConstructorParameters)
        try {
            for member in members {
                VisitDeclaration(member)
            }
        } finally {
            state.PopTypeMemberScope()
        }
    }

    func VisitStruct(structDeclaration: StructDeclaration) {
        members := structDeclaration.Members
        state.PushTypeMemberScope(members, structDeclaration.PrimaryConstructorParameters)
        try {
            for member in members {
                VisitDeclaration(member)
            }
        } finally {
            state.PopTypeMemberScope()
        }
    }

    func VisitRecord(recordDeclaration: RecordDeclaration) {
        members := recordDeclaration.Members
        state.PushTypeMemberScope(members, recordDeclaration.PrimaryConstructorParameters)
        try {
            for member in members {
                VisitDeclaration(member)
            }
        } finally {
            state.PopTypeMemberScope()
        }
    }

    // AN INTERFACE OPENS NO TYPE-MEMBER SCOPE, AND THAT ASYMMETRY IS REPRODUCED RATHER THAN TIDIED.
    // The C# walked an interface's members bare, so a name declared by an interface member does not
    // shadow the missing-import check the way a class's does. Whether that is right is a question for
    // a rule slice; it is not this slice's to change.
    func VisitInterface(interfaceDeclaration: InterfaceDeclaration) {
        for member in interfaceDeclaration.Members {
            VisitDeclaration(member)
        }
    }
}

// THE PUBLIC ENTRY. One `Linter` may lint many files, so every piece of per-file state is built inside
// `Lint` and thrown away with it; the only thing the object itself carries is the configuration.
class Linter {
    config: LinterConfig

    constructor(config: LinterConfig? = null) {
        this.config = config ?? LinterConfig.Default()
    }

    func Lint(ast: CompilationUnit, filePath: string? = null, sourceText: string? = null): List<Diagnostic> {
        state := new LinterWalkState(filePath, sourceText, config)
        declarationWalk := new LinterDeclarationWalk(state)
        declarationWalk.Visit(ast)
        return state.Diagnostics
    }
}
