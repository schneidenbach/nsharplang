namespace NSharpLang.Compiler.Ast

import System
import System.Collections
import System.Collections.Generic

public class AstChildrenCore {
    public static func Of(expression: object): List<object> {
        if expression == null {
            throw new ArgumentNullException("expression")
        }

        result := new List<object>()
        typeName := expression.GetType().Name

        if IsLeafExpression(typeName) {
            return result
        }

        if typeName == "InterpolatedStringExpression" {
            parts := GetRequiredList(expression, "Parts")
            index := 0
            while index < parts.Count {
                part := parts[index]
                if part != null && part.GetType().Name == "InterpolatedStringHole" {
                    AddRequiredProperty(result, part, "Expression")
                }

                index = index + 1
            }
            return result
        }

        if typeName == "RangeExpression" {
            AddOptionalProperty(result, expression, "Start")
            AddOptionalProperty(result, expression, "End")
            return result
        }

        if typeName == "BinaryExpression" {
            AddRequiredProperty(result, expression, "Left")
            AddRequiredProperty(result, expression, "Right")
            return result
        }

        if typeName == "UnaryExpression" {
            AddRequiredProperty(result, expression, "Operand")
            return result
        }

        if typeName == "MustExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "MemberAccessExpression" {
            AddRequiredProperty(result, expression, "Object")
            return result
        }

        if typeName == "IndexAccessExpression" {
            AddRequiredProperty(result, expression, "Object")
            AddRequiredProperty(result, expression, "Index")
            return result
        }

        if typeName == "CallExpression" {
            AddRequiredProperty(result, expression, "Callee")
            AddArgumentValues(result, GetRequiredList(expression, "Arguments"))
            return result
        }

        if typeName == "AssignmentExpression" {
            AddRequiredProperty(result, expression, "Target")
            AddRequiredProperty(result, expression, "Value")
            return result
        }

        if typeName == "LambdaExpression" {
            AddOptionalProperty(result, expression, "ExpressionBody")
            return result
        }

        if typeName == "OnSubscriptionExpression" {
            AddRequiredProperty(result, expression, "Target")
            AddRequiredProperty(result, expression, "Handler")
            return result
        }

        if typeName == "TernaryExpression" {
            AddRequiredProperty(result, expression, "Condition")
            AddRequiredProperty(result, expression, "ThenExpression")
            AddRequiredProperty(result, expression, "ElseExpression")
            return result
        }

        if typeName == "ArrayLiteralExpression" {
            AddListItems(result, GetRequiredList(expression, "Elements"))
            return result
        }

        if typeName == "TupleExpression" {
            AddTupleElementValues(result, GetRequiredList(expression, "Elements"))
            return result
        }

        if typeName == "ObjectInitializerExpression" {
            AddPropertyInitializerValues(result, GetRequiredList(expression, "Properties"))
            return result
        }

        if typeName == "NewExpression" {
            AddArgumentValues(result, GetRequiredList(expression, "ConstructorArguments"))
            AddOptionalProperty(result, expression, "Initializer")
            AddOptionalProperty(result, expression, "ArrayLengthExpression")
            return result
        }

        if typeName == "AllocExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "StackAllocExpression" {
            AddRequiredProperty(result, expression, "LengthExpression")
            return result
        }

        if typeName == "CastExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "IsExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "MatchExpression" {
            AddRequiredProperty(result, expression, "Value")
            AddMatchCaseValues(result, GetRequiredList(expression, "Cases"))
            return result
        }

        if typeName == "SpreadExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "WithExpression" {
            AddRequiredProperty(result, expression, "Target")
            AddPropertyInitializerValues(result, GetRequiredList(expression, "Properties"))
            return result
        }

        if typeName == "AwaitExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "ThrowExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "NameofExpression" {
            AddRequiredProperty(result, expression, "Target")
            return result
        }

        if typeName == "CheckedExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "UncheckedExpression" {
            AddRequiredProperty(result, expression, "Expression")
            return result
        }

        if typeName == "ParenthesizedExpression" {
            AddRequiredProperty(result, expression, "Inner")
            return result
        }

        throw new InvalidOperationException(
            "AstChildren.Of has no case for expression node '" + typeName + "'. Add it so AST walkers enumerate its children.")
    }

    static func IsLeafExpression(typeName: string): bool {
        return typeName == "IntLiteralExpression"
            || typeName == "FloatLiteralExpression"
            || typeName == "CharLiteralExpression"
            || typeName == "StringLiteralExpression"
            || typeName == "BoolLiteralExpression"
            || typeName == "NullLiteralExpression"
            || typeName == "IdentifierExpression"
            || typeName == "ThisExpression"
            || typeName == "BaseExpression"
            || typeName == "DefaultExpression"
            || typeName == "TypeOfExpression"
            || typeName == "SizeOfExpression"
    }

    static func AddArgumentValues(result: List<object>, arguments: IList) {
        index := 0
        while index < arguments.Count {
            argument := arguments[index]
            if argument != null {
                AddRequiredProperty(result, argument, "Value")
            }

            index = index + 1
        }
    }

    static func AddTupleElementValues(result: List<object>, elements: IList) {
        index := 0
        while index < elements.Count {
            element := elements[index]
            if element != null {
                AddRequiredProperty(result, element, "Value")
            }

            index = index + 1
        }
    }

    static func AddPropertyInitializerValues(result: List<object>, properties: IList) {
        index := 0
        while index < properties.Count {
            property := properties[index]
            if property != null {
                AddOptionalProperty(result, property, "IndexExpression")
                AddRequiredProperty(result, property, "Value")
            }

            index = index + 1
        }
    }

    static func AddMatchCaseValues(result: List<object>, cases: IList) {
        index := 0
        while index < cases.Count {
            matchCase := cases[index]
            if matchCase != null {
                AddOptionalProperty(result, matchCase, "Guard")
                AddRequiredProperty(result, matchCase, "Expression")
            }

            index = index + 1
        }
    }

    static func AddListItems(result: List<object>, values: IList) {
        index := 0
        while index < values.Count {
            value := values[index]
            if value != null {
                result.Add(value)
            }

            index = index + 1
        }
    }

    static func AddRequiredProperty(result: List<object>, owner: object, propertyName: string) {
        value := GetPropertyValue(owner, propertyName)
        if value == null {
            throw new InvalidOperationException(
                "AstChildren.Of expected '" + owner.GetType().Name + "." + propertyName + "' to contain an expression.")
        }

        result.Add(value)
    }

    static func AddOptionalProperty(result: List<object>, owner: object, propertyName: string) {
        value := GetPropertyValue(owner, propertyName)
        if value != null {
            result.Add(value)
        }
    }

    static func GetRequiredList(owner: object, propertyName: string): IList {
        value := GetPropertyValue(owner, propertyName)
        list := value as IList
        if list == null {
            throw new InvalidOperationException(
                "AstChildren.Of expected '" + owner.GetType().Name + "." + propertyName + "' to contain child expressions.")
        }

        return list
    }

    static func GetPropertyValue(owner: object, propertyName: string): object? {
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
