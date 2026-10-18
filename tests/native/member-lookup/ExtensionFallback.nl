namespace NSharpLang.MemberLookup.Tests

import System.Collections.Generic
import System.Linq

// EXTENSION METHODS ARE CANDIDATES WHEN NO INSTANCE METHOD OF THE NAME IS APPLICABLE (GitHub #236;
// C# §12.8.10.2). Member lookup answered with the receiver's instance methods alone, so the
// extension overloads were never considered and the call was NL402.
func instanceByLambdaShape(values: List<int>): int => values.FindAll(value => value > 15).Count

// A referenced extension: `List<int>` declares an instance `Contains(int)`, and
// `Enumerable.Contains(source, value, comparer)` is the only overload that takes a comparer.
func comparerExtension(values: List<int>): bool => values.Contains(20, EqualityComparer<int>.Default)

func comparerExtensionMissing(values: List<int>): bool => values.Contains(99, EqualityComparer<int>.Default)

func instanceContains(values: List<int>): bool => values.Contains(20)

func instanceByDelegate(values: List<int>): int => values.Find(value => value > 15)
