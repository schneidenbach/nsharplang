using NSharpLang.Cli;
using Xunit;

namespace NSharpLang.Tests;

public class CSharpToNSharpConverterTests
{
    [Fact]
    public void Convert_ApiControllerPatterns_EmitsNSharpSyntaxInsteadOfCSharpHybrid()
    {
        const string source = """
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace Demo.Api;

public class PeopleController : ControllerBase
{
    private readonly CotmDbContext _context;
    private readonly ILogger<PeopleController> _logger;

    public PeopleController(CotmDbContext context, ILogger<PeopleController> logger) : base()
    {
        _context = context;
        _logger = logger;
    }

    public IActionResult Get(int id)
    {
        using var activity = _logger.BeginScope("Get");
        if (id <= 0)
        {
            return BadRequest(new { Error = "bad", Id = id });
        }

        try
        {
            var dto = new PersonDto
            {
                Id = id,
                Name = _context.People.Find(id)!.Name,
                Status = id switch
                {
                    1 => "one",
                    _ => "other"
                }
            };
            return Ok(dto);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "failed");
            throw;
        }
    }
}
""";

        var result = new CSharpToNSharpConverter().Convert(source, "PeopleController.cs");

        Assert.True(result.Success, string.Join("\n", result.Diagnostics));
        Assert.Contains("import Microsoft.AspNetCore.Mvc", result.Output);
        Assert.Contains("context: CotmDbContext", result.Output);
        Assert.Contains("logger: ILogger<PeopleController>", result.Output);
        Assert.Contains("constructor(context: CotmDbContext, logger: ILogger<PeopleController>): base() {", result.Output);
        Assert.Contains("func Get(id: int): Result {", result.Output);
        Assert.Contains("this.context = context", result.Output);
        Assert.Contains("activity := logger.BeginScope(\"Get\")", result.Output);
        Assert.Contains("if id <= 0 {", result.Output);
        Assert.Contains("new() { Error: \"bad\", Id: id }", result.Output);
        Assert.Contains("Name: context.People.Find(id).Name", result.Output);
        Assert.Contains("Status: match id {", result.Output);
        Assert.Contains("catch {", result.Output);
        Assert.DoesNotContain("private readonly", result.Output);
        Assert.DoesNotContain("IActionResult", result.Output);
        Assert.DoesNotContain(";", result.Output);
        Assert.DoesNotContain("_context", result.Output);
        Assert.DoesNotContain("Find(id)!", result.Output);
        Assert.DoesNotContain("switch", result.Output);
        Assert.DoesNotContain("Error =", result.Output);
        Assert.DoesNotContain("if (", result.Output);
        Assert.DoesNotContain("catch (", result.Output);
    }

    [Fact]
    public void Convert_ApiProjectionPatterns_ConvertsRoslynExpressionsInsteadOfRawCSharp()
    {
        const string source = """
using System;
using System.Linq;

namespace Demo.Api;

public class ProjectionController
{
    public object Build(int[] ids)
    {
        var fallback = string.Empty;
        var values = new[] { 1, 2, 3 };
        var named = new string[] { "alpha", "beta" };
        var pair = (ids.Length, fallback);
        return ids.Select(id =>
        {
            if (id == 0)
            {
                return null;
            }

            return new PersonDto
            {
                Id = id,
                Name = names.TryGetValue(id, out var personName) ? personName : string.Empty,
                Values = values
            };
        }).ToList();
    }
}
""";

        var result = new CSharpToNSharpConverter().Convert(source, "ProjectionController.cs");

        Assert.True(result.Success, string.Join("\n", result.Diagnostics));
        Assert.Contains("fallback := string.Empty", result.Output);
        Assert.Contains("values := [1, 2, 3]", result.Output);
        Assert.Contains("named := [\"alpha\", \"beta\"]", result.Output);
        Assert.Contains("pair := (ids.Length, fallback)", result.Output);
        Assert.Contains("names.TryGetValue(id, out personName) ? personName : string.Empty", result.Output);
        Assert.Contains("if id == 0 { return null }", result.Output);
        Assert.Contains("return new PersonDto() { Id: id, Name:", result.Output);
        Assert.DoesNotContain("new[]", result.Output);
        Assert.DoesNotContain("new string[]", result.Output);
        Assert.DoesNotContain("out var", result.Output);
        Assert.DoesNotContain("Name =", result.Output);
        Assert.DoesNotContain("Unsupported expression", result.Output);
        Assert.Empty(result.Diagnostics);
    }
}
