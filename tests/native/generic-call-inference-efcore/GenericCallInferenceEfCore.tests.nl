namespace NSharpLang.GenericCallInferenceEfCore.Tests

import System
import Microsoft.EntityFrameworkCore
import Microsoft.Extensions.DependencyInjection

// The EF Core shapes behind the generic-call-inference rows, run against the real packages. A row
// reads the SQL and parameters EF built through `ToQueryString()`, so the selected method is proved by
// what it did, not only by the call compiling.

class Person {
    Id: Guid
    Name: string
}

// A context that takes its options from the container, which `AddDbContext` requires.
class Pooled: DbContext {
    constructor(options: DbContextOptions<Pooled>): base(options) {
    }
}

class Db: DbContext {
    People: DbSet<Person>

    protected override func OnConfiguring(options: DbContextOptionsBuilder) {
        options.UseNpgsql("Host=localhost;Database=generic-call-inference")
    }

    func peopleViaThis(): DbSet<Person> {
        return this.Set<Person>()
    }

    func peopleViaBare(): DbSet<Person> {
        return Set<Person>()
    }

    func peopleLocal(): int {
        set := Set<Person>()
        return set != null ? 1 : 0
    }
}

func FreshSet(): DbSet<Person> {
    return new Db().Set<Person>()
}

// Npgsql's query string lists each parameter on a `-- pN='value'` line ahead of the SQL.
func DeclareCount(sql: string): int {
    return sql.Split("-- p").Length - 1
}

test "FromSqlRaw infers its type argument from the receiver and packs one argument" {
    n := "a"
    sql := FreshSet().FromSqlRaw("SELECT * FROM People WHERE Name = {0}", n).ToQueryString()
    assert sql.Contains("p0='a'"), sql
    assert DeclareCount(sql) == 1, sql
}

test "FromSqlRaw packs several arguments of different types into the object array" {
    sql := FreshSet().FromSqlRaw("SELECT * FROM People WHERE Name = {0} AND Id <> {1}", "a", 5).ToQueryString()
    assert DeclareCount(sql) == 2, sql
    assert sql.Contains("='5'"), sql
}

test "FromSqlRaw packs an int into the object array" {
    sql := FreshSet().FromSqlRaw("SELECT * FROM People WHERE Id = {0}", 5).ToQueryString()
    assert DeclareCount(sql) == 1, sql
    assert sql.Contains("='5'"), sql
}

test "FromSqlRaw infers its type argument and packs no arguments" {
    sql := FreshSet().FromSqlRaw("SELECT * FROM People").ToQueryString()
    assert sql.Contains("SELECT * FROM People"), sql
    assert DeclareCount(sql) == 0, sql
}

test "FromSqlRaw passes an already-built object array through unpacked" {
    args: object[] = ["a", "b", "c"]
    sql := FreshSet().FromSqlRaw("SELECT * FROM People WHERE Name IN ({0}, {1}, {2})", args).ToQueryString()
    assert DeclareCount(sql) == 3, sql
}

func fromSqlRawNullParameterName(): string {
    try {
        FreshSet().FromSqlRaw("SELECT * FROM People", null)
        return "returned query"
    } catch ex: ArgumentNullException {
        return ex.ParamName ?? ""
    }
}

// A lone `null` converts to the `object[]` itself (the normal form), as in C#: EF is handed a null
// array and refuses it, rather than receiving one null parameter.
test "a lone null reaches FromSqlRaw as the array, not as a packed element" {
    assert fromSqlRawNullParameterName() == "parameters"
}

test "the static spelling of FromSqlRaw infers its type argument and packs its tail" {
    n := "a"
    sql := RelationalQueryableExtensions.FromSqlRaw(FreshSet(), "SELECT * FROM People WHERE Name = {0}", n).ToQueryString()
    assert DeclareCount(sql) == 1, sql
    assert sql.Contains("p0='a'"), sql
}

test "control: FromSqlRaw with the type argument written packs its tail" {
    sql := FreshSet().FromSqlRaw<Person>("SELECT * FROM People WHERE Name = {0}", "a").ToQueryString()
    assert DeclareCount(sql) == 1, sql
}

test "control: FromSqlRaw with the type argument written and nothing packed" {
    sql := FreshSet().FromSqlRaw<Person>("SELECT * FROM People").ToQueryString()
    assert DeclareCount(sql) == 0, sql
}

test "AddDbContext with a written type argument binds an inline options lambda that configures the context" {
    services := new ServiceCollection()
    services.AddDbContext<Pooled>(o => o.UseNpgsql("Host=localhost;Database=generic-call-inference"))
    provider := services.BuildServiceProvider()
    options := provider.GetRequiredService<DbContextOptions<Pooled>>()
    assert options != null
    context := provider.GetRequiredService<Pooled>()
    assert (context.Database.ProviderName ?? "").Contains("Npgsql")
    context.Dispose()
    provider.Dispose()
}

test "AddDbContext with a written type argument binds a typed Action local" {
    services := new ServiceCollection()
    act: Action<DbContextOptionsBuilder> = o => o.UseNpgsql("Host=localhost;Database=generic-call-inference")
    services.AddDbContext<Pooled>(act)
    provider := services.BuildServiceProvider()
    options := provider.GetRequiredService<DbContextOptions<Pooled>>()
    assert options != null
    context := provider.GetRequiredService<Pooled>()
    assert (context.Database.ProviderName ?? "").Contains("Npgsql")
    context.Dispose()
    provider.Dispose()
}

test "Set<T> resolves on this, on the implicit receiver and into a local inside a DbContext subclass" {
    db := new Db()
    assert db.peopleViaThis() != null
    assert db.peopleViaBare() != null
    assert db.peopleLocal() == 1
}
