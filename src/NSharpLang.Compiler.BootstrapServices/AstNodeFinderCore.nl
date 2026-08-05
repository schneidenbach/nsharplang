namespace NSharpLang.Compiler

import System
import System.Collections

class AstNodeFinderCore {
    static func FindExpressionAtPosition(ast: object, line: int, column: int): object? {
        visitor := new AstPositionVisitor(line, column)
        visitor.VisitCompilationUnit(ast)
        return visitor.FoundExpression
    }
}

class AstPositionVisitor {
    targetLine: int
    targetColumn: int
    foundExpressionValue: object?

    FoundExpression: object? => foundExpressionValue

    constructor(line: int, column: int) {
        targetLine = line
        targetColumn = column
    }

    func VisitCompilationUnit(unit: object) {
        declarations := GetOptionalList(unit, "Declarations")
        if declarations == null {
            return
        }

        index := 0
        while index < declarations.Count {
            declaration := declarations[index]
            if declaration != null {
                VisitDeclaration(declaration)
                if foundExpressionValue != null {
                    return
                }
            }

            index = index + 1
        }
    }

    func VisitDeclaration(declaration: object) {
        typeName := declaration.GetType().Name

        if typeName == "FunctionDeclaration" {
            body := GetOptionalProperty(declaration, "Body")
            if body != null {
                VisitStatement(body)
            }
            return
        }

        if typeName == "ClassDeclaration" {
            members := GetOptionalList(declaration, "Members")
            if members == null {
                return
            }

            index := 0
            while index < members.Count {
                member := members[index]
                if member != null {
                    VisitDeclaration(member)
                    if foundExpressionValue != null {
                        return
                    }
                }

                index = index + 1
            }
        }
    }

    func VisitStatement(statement: object) {
        typeName := statement.GetType().Name

        if typeName == "BlockStatement" {
            statements := GetRequiredList(statement, "Statements")
            index := 0
            while index < statements.Count {
                child := statements[index]
                if child != null {
                    VisitStatement(child)
                    if foundExpressionValue != null {
                        return
                    }
                }

                index = index + 1
            }
            return
        }

        if typeName == "ExpressionStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Expression")))
            return
        }

        if typeName == "VariableDeclarationStatement" {
            initializer := GetOptionalProperty(statement, "Initializer")
            if initializer != null {
                SetFoundExpression(FindExpression(initializer))
            }
            return
        }

        if typeName == "ReturnStatement" {
            value := GetOptionalProperty(statement, "Value")
            if value != null {
                SetFoundExpression(FindExpression(value))
            }
            return
        }

        if typeName == "PrintStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Value")))
            return
        }

        if typeName == "IfStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Condition")))
            if foundExpressionValue != null {
                return
            }

            VisitStatement(GetRequiredProperty(statement, "ThenStatement"))
            if foundExpressionValue != null {
                return
            }

            elseStatement := GetOptionalProperty(statement, "ElseStatement")
            if elseStatement != null {
                VisitStatement(elseStatement)
            }
            return
        }

        if typeName == "WhileStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Condition")))
            if foundExpressionValue != null {
                return
            }

            VisitStatement(GetRequiredProperty(statement, "Body"))
            return
        }

        if typeName == "ForStatement" {
            initializer := GetOptionalProperty(statement, "Initializer")
            if initializer != null {
                VisitStatement(initializer)
                if foundExpressionValue != null {
                    return
                }
            }

            condition := GetOptionalProperty(statement, "Condition")
            if condition != null {
                SetFoundExpression(FindExpression(condition))
                if foundExpressionValue != null {
                    return
                }
            }

            iterator := GetOptionalProperty(statement, "Iterator")
            if iterator != null {
                SetFoundExpression(FindExpression(iterator))
                if foundExpressionValue != null {
                    return
                }
            }

            VisitStatement(GetRequiredProperty(statement, "Body"))
            return
        }

        if typeName == "ForeachStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Collection")))
            if foundExpressionValue != null {
                return
            }

            VisitStatement(GetRequiredProperty(statement, "Body"))
        }
    }

    func FindExpression(expression: object): object? {
        currentMatch: object? = null
        if IsAtPosition(GetRequiredInt(expression, "Line"), GetRequiredInt(expression, "Column")) {
            currentMatch = expression
        }

        typeName := expression.GetType().Name

        if typeName == "BinaryExpression" {
            bestMatch := ChooseBestExpression(currentMatch, FindExpression(GetRequiredProperty(expression, "Left")))
            bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(expression, "Right")))
            return bestMatch
        }

        if typeName == "UnaryExpression" {
            childMatch := FindExpression(GetRequiredProperty(expression, "Operand"))
            return ChooseBestExpression(currentMatch, childMatch)
        }

        if typeName == "MustExpression" {
            childMatch := FindExpression(GetRequiredProperty(expression, "Expression"))
            return ChooseBestExpression(currentMatch, childMatch)
        }

        if typeName == "CallExpression" {
            bestMatch := ChooseBestExpression(currentMatch, FindExpression(GetRequiredProperty(expression, "Callee")))

            arguments := GetRequiredList(expression, "Arguments")
            index := 0
            while index < arguments.Count {
                argument := arguments[index]
                if argument != null {
                    bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(argument, "Value")))
                }

                index = index + 1
            }

            return bestMatch
        }

        if typeName == "MemberAccessExpression" {
            return ChooseBestExpression(FindExpression(GetRequiredProperty(expression, "Object")), currentMatch)
        }

        if typeName == "IndexAccessExpression" {
            bestMatch := ChooseBestExpression(currentMatch, FindExpression(GetRequiredProperty(expression, "Object")))
            bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(expression, "Index")))
            return bestMatch
        }

        if typeName == "ArrayLiteralExpression" {
            bestMatch := currentMatch
            elements := GetRequiredList(expression, "Elements")
            index := 0
            while index < elements.Count {
                element := elements[index]
                if element != null {
                    bestMatch = ChooseBestExpression(bestMatch, FindExpression(element))
                }

                index = index + 1
            }

            return bestMatch
        }

        if typeName == "LambdaExpression" {
            expressionBody := GetOptionalProperty(expression, "ExpressionBody")
            if expressionBody != null {
                childMatch := FindExpression(expressionBody)
                return ChooseBestExpression(currentMatch, childMatch)
            }

            blockBody := GetOptionalProperty(expression, "BlockBody")
            if blockBody != null {
                previousFound := foundExpressionValue
                foundExpressionValue = null
                VisitStatement(blockBody)
                childMatch := foundExpressionValue
                foundExpressionValue = previousFound
                return ChooseBestExpression(currentMatch, childMatch)
            }

            return currentMatch
        }

        if typeName == "ParenthesizedExpression" {
            childMatch := FindExpression(GetRequiredProperty(expression, "Inner"))
            return ChooseBestExpression(currentMatch, childMatch)
        }

        return currentMatch
    }

    func SetFoundExpression(expression: object?) {
        if expression != null {
            foundExpressionValue = expression
        }
    }

    func ChooseBestExpression(current: object?, candidate: object?): object? {
        if current == null {
            return candidate
        }

        if candidate == null {
            return current
        }

        currentLine := Math.Max(0, GetRequiredInt(current, "Line") - 1)
        candidateLine := Math.Max(0, GetRequiredInt(candidate, "Line") - 1)
        if currentLine != targetLine {
            return candidate
        }

        if candidateLine != targetLine {
            return current
        }

        currentColumn := Math.Max(0, GetRequiredInt(current, "Column") - 1)
        candidateColumn := Math.Max(0, GetRequiredInt(candidate, "Column") - 1)
        if candidateColumn >= currentColumn && candidateColumn <= targetColumn {
            return candidate
        }

        return current
    }

    func IsAtPosition(line: int, column: int): bool {
        nodeLine := Math.Max(0, line - 1)
        nodeColumn := Math.Max(0, column - 1)
        return nodeLine == targetLine && nodeColumn <= targetColumn
    }

    static func GetRequiredList(owner: object, propertyName: string): IList {
        value := GetRequiredProperty(owner, propertyName)
        list := value as IList
        if list == null {
            throw new InvalidOperationException("AstNodeFinder expected a list.")
        }

        return list
    }

    static func GetRequiredInt(owner: object, propertyName: string): int {
        return Convert.ToInt32(GetRequiredProperty(owner, propertyName))
    }

    static func GetRequiredProperty(owner: object, propertyName: string): object {
        value := GetOptionalProperty(owner, propertyName)
        if value == null {
            throw new InvalidOperationException("AstNodeFinder expected a property.")
        }

        return value
    }

    static func GetOptionalList(owner: object, propertyName: string): IList? {
        value := GetOptionalProperty(owner, propertyName)
        if value == null {
            return null
        }

        list := value as IList
        if list == null {
            throw new InvalidOperationException("AstNodeFinder expected a list.")
        }

        return list
    }

    static func GetOptionalProperty(owner: object, propertyName: string): object? {
        property := owner.GetType().GetProperty(propertyName)
        if property != null {
            return property.GetValue(owner)
        }

        field := owner.GetType().GetField(propertyName)
        if field != null {
            return field.GetValue(owner)
        }

        return null
    }
}
