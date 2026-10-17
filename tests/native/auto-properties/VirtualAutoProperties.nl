namespace NSharpLang.AutoProperties.Tests

import System
import System.Collections.Generic
import Microsoft.EntityFrameworkCore

// VIRTUAL, ABSTRACT AND OVERRIDE BARE MEMBERS (website/docs/types.md "Fields and properties").
// `virtual Name: T` is C#'s `public virtual T Name { get; set; }`, and every body in this assembly
// reaches it through the accessors, so an override — a derived class's or a runtime proxy's — is
// honoured by the declaring type's own code too.
interface IGaugeLabel {
    Label: string
}

class Gauge: IGaugeLabel {
    virtual Label: string = "gauge"
    virtual Reading: int
    virtual Notes: string?
    protected virtual Calibration: int = 1

    func Describe(): string => Label + "=" + Reading.ToString()

    func Step(): int {
        Reading++
        Reading += 10
        this.Reading += 100
        return Reading
    }

    func Rename(label: string) {
        Label = label
    }

    func Reader(): Func<string> => () => Label + ":" + Reading.ToString()

    func CalibrationValue(): int => Calibration
}

// An override owns its own storage, as C#'s overriding `{ get; set; }` does: the base's initializer
// still fills the base's storage, which only `base.Label` can read.
class LoudGauge: Gauge {
    override Label: string = "loud"
    override Reading: int = 1000
    override Calibration: int = 7

    func BaseLabel(): string => base.Label
}

class FinalGauge: LoudGauge {
    sealed override Label: string = "final"
}

abstract class Shape {
    abstract Name: string
    abstract Tag: string?

    func Show(): string => "shape " + Name
}

class Square: Shape {
    override Name: string = "square"
    override Tag: string?
}

class Holder<T> {
    virtual Value: T

    func Read(): T => Value
}

class IntHolder: Holder<int> {
    override Value: int = 42
}

// A base from the BCL: `Exception.HelpLink` is `public virtual string? HelpLink { get; set; }`.
class GaugeError: Exception {
    override HelpLink: string? = "https://example.test/help"
}

// No N# type derives from a record, but its CLR type is unsealed, so a runtime proxy can override a
// virtual member of one; `with` and equality keep working through the accessors and the storage.
record Sample {
    virtual Label: string = ""
    virtual Count: int
}

// ---- EF Core lazy-loading proxies ------------------------------------------------------------
//
// `UseLazyLoadingProxies()` refuses a model whose navigations are not virtual, and the proxy it
// generates overrides each navigation's getter to load on first read. `AuthorName()` reads `Author`
// from INSIDE `Book`, so it loads only because the body dispatches through the getter.
class Author {
    Id: int
    Name: string = ""
    virtual Books: ICollection<Book> = new List<Book>()
}

class Book {
    Id: int
    Title: string = ""
    AuthorId: int
    virtual Author: Author?

    func AuthorName(): string {
        author := Author
        if author == null {
            return "none"
        }
        return author.Name
    }
}

class Library: DbContext {
    Authors: DbSet<Author>
    Books: DbSet<Book>

    protected override func OnConfiguring(options: DbContextOptionsBuilder) {
        options.UseLazyLoadingProxies().UseInMemoryDatabase("virtual-auto-properties-library")
    }
}
