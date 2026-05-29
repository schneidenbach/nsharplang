using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Selective generic specialization (monomorphization) policy + registry for the IL
/// backend. This is the highest-risk performance pass for GC-safety, so it is
/// deliberately conservative: it ONLY specializes private/file-private/local generic
/// functions over value-type instantiations, NEVER public CLR surface (to preserve C#
/// interop), and caps the total number of specialized bodies emitted to avoid code-size
/// blowup.
/// </summary>
/// <remarks>
/// <para>
/// Design rationale (the #160 lesson): we do NOT rewrite IL tokens after the fact.
/// Instead the emitter re-drives its existing, type-correct body emission with the
/// generic type parameters bound to concrete value types via a substitution map. Every
/// local, signature, <c>ldtoken</c>, <c>newobj</c>, and array element type therefore
/// flows through the same resolution code that already produces verifiable IL for
/// ordinary non-generic methods. The only token that changes at the call site is the
/// target method, which becomes a concrete non-generic method instead of a closed
/// generic instantiation (<c>foo&lt;int32&gt;</c> -&gt; <c>foo$int32</c>).
/// </para>
/// <para>
/// This type owns no IL emission; it is a pure policy/registry the
/// <c>ILCompiler</c> consults. Emission of the specialized body is performed by the
/// compiler against the <see cref="MethodBuilder"/> registered here.
/// </para>
/// </remarks>
public sealed class GenericSpecializer
{
    /// <summary>
    /// Default upper bound on the number of specialized method bodies emitted in a single
    /// compilation. Specialization trades assembly size for hot-path codegen; this cap keeps
    /// pathological generic-heavy programs from exploding the output.
    /// </summary>
    public const int DefaultSpecializationCap = 256;

    private readonly int _cap;

    // Registry of declared specializations, keyed by (generic declaration, concrete type args).
    private readonly Dictionary<SpecializationKey, GenericSpecialization> _specializations = new();

    // Records why a candidate instantiation was not specialized, for diagnostics / IL-shape reports.
    private readonly List<SkippedSpecialization> _skipped = new();

    public GenericSpecializer(int cap = DefaultSpecializationCap)
    {
        if (cap < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(cap), cap, "Specialization cap cannot be negative.");
        }

        _cap = cap;
    }

    /// <summary>All specializations registered so far.</summary>
    public IReadOnlyCollection<GenericSpecialization> Specializations => _specializations.Values;

    /// <summary>Diagnostics describing instantiations that were considered but not specialized.</summary>
    public IReadOnlyList<SkippedSpecialization> Skipped => _skipped;

    /// <summary>The number of specialized bodies registered.</summary>
    public int Count => _specializations.Count;

    /// <summary>
    /// Determines whether a generic function is eligible for specialization at all, based on
    /// its ABI boundary. Public CLR surface is never specialized so its generic ABI stays
    /// intact for C# interop. A non-generic function is trivially ineligible.
    /// </summary>
    public static bool IsEligibleBoundary(AbiBoundary boundary) =>
        boundary is AbiBoundary.ClrInternal or AbiBoundary.FilePrivate or AbiBoundary.Local;

    /// <summary>
    /// Returns <c>true</c> when the supplied type arguments are all concrete value types that
    /// are safe to specialize over. Reference types are excluded (the CLR already shares their
    /// code via <c>__Canon</c> and specializing buys nothing), and so are open generic
    /// parameters, pointers, by-ref types, and <c>void</c>.
    /// </summary>
    public static bool AreSpecializableValueTypeArguments(IReadOnlyList<Type> typeArguments)
    {
        if (typeArguments.Count == 0)
        {
            return false;
        }

        foreach (var type in typeArguments)
        {
            if (!IsSpecializableValueType(type))
            {
                return false;
            }
        }

        return true;
    }

    /// <summary>
    /// A single type argument is specializable when it is a closed (no open generic parameters)
    /// value type that is not a pointer, by-ref, or generic-parameter placeholder. We
    /// conservatively also exclude <see cref="TypeBuilder"/>-backed value types because their
    /// layout may not be finalized when the specialized signature is built; the shared generic
    /// path remains correct for those.
    /// </summary>
    public static bool IsSpecializableValueType(Type type)
    {
        if (type is null)
        {
            return false;
        }

        if (type.IsByRef || type.IsPointer || type.IsGenericParameter)
        {
            return false;
        }

        if (type.ContainsGenericParameters)
        {
            return false;
        }

        if (!type.IsValueType)
        {
            return false;
        }

        if (type == typeof(void))
        {
            return false;
        }

        // Source-declared structs are emitted as TypeBuilders; their full layout/members are
        // not necessarily baked when we build the specialized signature. Specializing over them
        // is feasible but raises the GC-safety risk surface, so we stay conservative and leave
        // them on the shared generic path until proven safe by evidence.
        if (type is TypeBuilder)
        {
            return false;
        }

        return true;
    }

    /// <summary>
    /// Looks up an already-registered specialization for the given declaration and concrete
    /// type arguments.
    /// </summary>
    public bool TryGet(FunctionDeclaration declaration, IReadOnlyList<Type> typeArguments, out GenericSpecialization specialization)
    {
        return _specializations.TryGetValue(new SpecializationKey(declaration, typeArguments), out specialization!);
    }

    /// <summary>
    /// Registers a specialization for the given declaration and concrete value-type arguments,
    /// associating it with the supplied non-generic <paramref name="builder"/>. Returns the
    /// existing registration if one was already created for the same key (idempotent). Returns
    /// <c>null</c> when the request is rejected (ineligible boundary, non-value-type arguments,
    /// or the cap has been reached) — the caller must then fall back to the shared generic path.
    /// </summary>
    /// <param name="declaration">The open generic function declaration.</param>
    /// <param name="boundary">The ABI boundary the declaration sits on.</param>
    /// <param name="typeArguments">The concrete type arguments for this instantiation.</param>
    /// <param name="builderFactory">
    /// Factory invoked to create the specialized <see cref="MethodBuilder"/> the first time a
    /// key is registered. Only called when the request is accepted and not already present.
    /// </param>
    public GenericSpecialization? Register(
        FunctionDeclaration declaration,
        AbiBoundary boundary,
        IReadOnlyList<Type> typeArguments,
        Func<MethodBuilder> builderFactory)
    {
        ArgumentNullException.ThrowIfNull(declaration);
        ArgumentNullException.ThrowIfNull(typeArguments);
        ArgumentNullException.ThrowIfNull(builderFactory);

        var key = new SpecializationKey(declaration, typeArguments);
        if (_specializations.TryGetValue(key, out var existing))
        {
            return existing;
        }

        if (!IsEligibleBoundary(boundary))
        {
            RecordSkip(declaration, typeArguments, $"boundary {boundary} is part of the public CLR surface");
            return null;
        }

        if (!AreSpecializableValueTypeArguments(typeArguments))
        {
            RecordSkip(declaration, typeArguments, "not all type arguments are specializable value types");
            return null;
        }

        if (_specializations.Count >= _cap)
        {
            RecordSkip(declaration, typeArguments, $"specialization cap ({_cap}) reached");
            return null;
        }

        var builder = builderFactory()
            ?? throw new InvalidOperationException("Specialization builder factory returned null.");

        var specialization = new GenericSpecialization(declaration, typeArguments.ToArray(), builder);
        _specializations[key] = specialization;
        return specialization;
    }

    private void RecordSkip(FunctionDeclaration declaration, IReadOnlyList<Type> typeArguments, string reason)
    {
        _skipped.Add(new SkippedSpecialization(declaration.Name, typeArguments.Select(FormatType).ToArray(), reason));
    }

    private static string FormatType(Type type) => type?.FullName ?? type?.Name ?? "<null>";

    /// <summary>Identity of a specialization request: the declaration plus its ordered type arguments.</summary>
    private readonly struct SpecializationKey : IEquatable<SpecializationKey>
    {
        private readonly FunctionDeclaration _declaration;
        private readonly Type[] _typeArguments;

        public SpecializationKey(FunctionDeclaration declaration, IReadOnlyList<Type> typeArguments)
        {
            _declaration = declaration;
            _typeArguments = typeArguments.ToArray();
        }

        public bool Equals(SpecializationKey other)
        {
            if (!ReferenceEquals(_declaration, other._declaration))
            {
                return false;
            }

            if (_typeArguments.Length != other._typeArguments.Length)
            {
                return false;
            }

            for (var i = 0; i < _typeArguments.Length; i++)
            {
                if (_typeArguments[i] != other._typeArguments[i])
                {
                    return false;
                }
            }

            return true;
        }

        public override bool Equals(object? obj) => obj is SpecializationKey other && Equals(other);

        public override int GetHashCode()
        {
            var hash = new HashCode();
            hash.Add(System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(_declaration));
            foreach (var type in _typeArguments)
            {
                hash.Add(type);
            }

            return hash.ToHashCode();
        }
    }
}

/// <summary>
/// A registered specialization: the open generic declaration, the concrete value-type
/// arguments it was specialized for, and the non-generic <see cref="MethodBuilder"/> that
/// carries the monomorphic body.
/// </summary>
public sealed class GenericSpecialization
{
    public GenericSpecialization(FunctionDeclaration declaration, Type[] typeArguments, MethodBuilder builder)
    {
        Declaration = declaration;
        TypeArguments = typeArguments;
        Builder = builder;
    }

    /// <summary>The open generic function declaration this specialization derives from.</summary>
    public FunctionDeclaration Declaration { get; }

    /// <summary>The concrete value-type arguments, in declaration order.</summary>
    public IReadOnlyList<Type> TypeArguments { get; }

    /// <summary>The non-generic method that carries the specialized body.</summary>
    public MethodBuilder Builder { get; }

    /// <summary>
    /// Builds the type-parameter-name -&gt; concrete-type substitution map used to re-drive
    /// body emission. The declaration's type parameters are zipped positionally with
    /// <see cref="TypeArguments"/>.
    /// </summary>
    public IReadOnlyDictionary<string, Type> CreateSubstitution()
    {
        var typeParameters = Declaration.TypeParameters
            ?? throw new InvalidOperationException($"Specialized declaration '{Declaration.Name}' has no type parameters.");

        if (typeParameters.Count != TypeArguments.Count)
        {
            throw new InvalidOperationException(
                $"Specialization arity mismatch for '{Declaration.Name}': {typeParameters.Count} type parameters but {TypeArguments.Count} type arguments.");
        }

        var map = new Dictionary<string, Type>(StringComparer.Ordinal);
        for (var i = 0; i < typeParameters.Count; i++)
        {
            map[typeParameters[i].Name] = TypeArguments[i];
        }

        return map;
    }
}

/// <summary>Diagnostic record describing an instantiation that was considered but not specialized.</summary>
public readonly record struct SkippedSpecialization(string Name, IReadOnlyList<string> TypeArguments, string Reason);
