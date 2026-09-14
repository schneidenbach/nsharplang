namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection

class BareCatchTypeEmitProbe {
    static func EmptyTypes(): Type[] {
        return new Type[](0)
    }

    static func EmptyArguments(): object?[] {
        return new object?[](0)
    }

    static func SetArgument(values: object?[], index: int, value: object?) {
        values[index] = value
    }

    static func RequiredMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
        method := owner.GetMethod(name, parameterTypes)
        if method == null {
            throw new InvalidOperationException("Required method '" + owner.get_FullName() + "." + name + "' was not found.")
        }
        return method
    }

    static func RequiredInvocation(method: MethodInfo, receiver: object?, values: object?[]): object {
        result := method.Invoke(receiver, values)
        if result == null {
            throw new InvalidOperationException("Required reflection invocation returned null.")
        }
        return result
    }

    static func RequiredProperty(receiver: object, name: string): object {
        property := receiver.GetType().GetProperty(name)
        if property == null {
            throw new InvalidOperationException("Required property '" + name + "' was not found.")
        }
        value := property.GetValue(receiver)
        if value == null {
            throw new InvalidOperationException("Required property '" + name + "' was null.")
        }
        return value
    }

    static func HandlerType(methodName: string): Type {
        method := RequiredMethod(typeof(BareCatchTypeEmitProbe), methodName, EmptyTypes())
        getBody := RequiredMethod(typeof(MethodBase), "GetMethodBody", EmptyTypes())
        body := RequiredInvocation(getBody, method, EmptyArguments())
        clauses := RequiredProperty(body, "ExceptionHandlingClauses")
        count := Convert.ToInt32(RequiredProperty(clauses, "Count"))
        if count != 1 {
            throw new InvalidOperationException("Expected exactly one exception-handling clause.")
        }

        itemProperty := clauses.GetType().GetProperty("Item")
        if itemProperty == null {
            throw new InvalidOperationException("Exception-handling clauses exposed no indexer.")
        }
        indexArguments := new object?[](1)
        SetArgument(indexArguments, 0, 0)
        clause := itemProperty.GetValue(clauses, indexArguments)
        if clause == null {
            throw new InvalidOperationException("The first exception-handling clause was null.")
        }
        catchType := RequiredProperty(clause, "CatchType") as Type
        if catchType == null {
            throw new InvalidOperationException("The first clause exposed no catch type.")
        }
        return catchType
    }

    static func BareResult(): int {
        try {
            throw new InvalidOperationException("bare")
        } catch {
            return 11
        }
    }

    static func ExceptionResult(): int {
        try {
            throw new InvalidOperationException("exception")
        } catch error: Exception {
            return 13
        }
    }

    static func ArgumentResult(): int {
        try {
            throw new ArgumentException("argument")
        } catch error: ArgumentException {
            return 17
        }
    }
}

test "bare catch metadata and execution retain the CLR catch-all distinction" {
    assert BareCatchTypeEmitProbe.BareResult() == 11
    assert BareCatchTypeEmitProbe.ExceptionResult() == 13
    assert BareCatchTypeEmitProbe.ArgumentResult() == 17
    assert BareCatchTypeEmitProbe.HandlerType("BareResult") == typeof(object)
    assert BareCatchTypeEmitProbe.HandlerType("ExceptionResult") == typeof(Exception)
    assert BareCatchTypeEmitProbe.HandlerType("ArgumentResult") == typeof(ArgumentException)
}
