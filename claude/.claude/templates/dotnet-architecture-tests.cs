// ArchitectureTests.cs — enforces the slice and layer conventions in both dispatch variants.
// See .claude/docs/testing.md "Architecture tests". Copy to
// tests/Architecture.Tests/ArchitectureTests.cs and replace:
//   {Namespace}        root namespace (e.g. Acme.Orders)
//   {DomainType}       any type in the assembly holding Domain/ (e.g. IAggregateRoot)
//   {ApplicationType}  any type in the assembly holding Application/ (e.g. DependencyInjection
//                      in the 4-project layout, Program in a 1-project layout)
// Then DELETE the variant block that does not apply ("Mediator only" or "Direct handlers only").
//
// Packages: xunit, Shouldly, NetArchTest.Rules. Every rule is namespace- or reflection-based and
// matches handler interfaces by name, so the file compiles in either variant and holds in the
// 4-, 2- and 1-project layouts (namespaces do not change when assemblies collapse).

using System.Reflection;
using FluentValidation;
using NetArchTest.Rules;
using Shouldly;

namespace {Namespace}.Architecture.Tests;

public sealed class ArchitectureTests
{
    private const string DomainNs = "{Namespace}.Domain";
    private const string ApplicationNs = "{Namespace}.Application";
    private const string InfrastructureNs = "{Namespace}.Infrastructure";
    private const string ApiNs = "{Namespace}.Api";
    private const string FeaturesNs = "{Namespace}.Application.Features";

    private static readonly Assembly DomainAssembly = typeof({DomainType}).Assembly;
    private static readonly Assembly ApplicationAssembly = typeof({ApplicationType}).Assembly;
    private static readonly Assembly[] Assemblies = new[] { DomainAssembly, ApplicationAssembly }.Distinct().ToArray();

    // ── Layers ────────────────────────────────────────────────────────────────

    [Fact]
    public void Domain_Should_NotDependOnOuterLayers_When_Compiled()
    {
        var result = Types.InAssemblies(Assemblies)
            .That().ResideInNamespace(DomainNs)
            .ShouldNot().HaveDependencyOnAny(ApplicationNs, InfrastructureNs, ApiNs, "Microsoft.EntityFrameworkCore")
            .GetResult();

        result.FailingTypeNames.ShouldBeNull();
    }

    [Fact]
    public void Application_Should_NotDependOnInfrastructureOrHttp_When_Compiled()
    {
        var result = Types.InAssemblies(Assemblies)
            .That().ResideInNamespace(ApplicationNs)
            .ShouldNot().HaveDependencyOnAny(InfrastructureNs, ApiNs, "FastEndpoints", "Microsoft.AspNetCore.Http")
            .GetResult();

        result.FailingTypeNames.ShouldBeNull();
    }

    // ── Slices ────────────────────────────────────────────────────────────────

    [Fact]
    public void Handlers_Should_BeNestedInTheirRequest_When_Declared()
    {
        var offenders = HandlerTypes()
            .Where(t => !(t.IsNested && t.Name == "Handler" && IsRequest(t.DeclaringType!)))
            .Select(t => t.FullName)
            .ToList();

        offenders.ShouldBeEmpty("Handlers must be a nested class named Handler inside their ...Command/...Query record");
    }

    [Fact]
    public void Validators_Should_BeNestedInTheirRequest_When_Declared()
    {
        var offenders = FeatureTypes()
            .Where(t => InheritsOpenGeneric(t, typeof(AbstractValidator<>)))
            .Where(t => !(t.IsNested && t.Name == "Validator" && IsRequest(t.DeclaringType!)))
            .Select(t => t.FullName)
            .ToList();

        offenders.ShouldBeEmpty("Validators must be a nested class named Validator inside their ...Command/...Query record");
    }

    [Fact]
    public void Features_Should_NotReferenceOtherFeatures_When_Compiled()
    {
        var features = FeatureTypes()
            .Select(t => t.Namespace!)
            .Where(ns => ns.StartsWith(FeaturesNs + ".", StringComparison.Ordinal))
            .Select(ns => ns[(FeaturesNs.Length + 1)..].Split('.')[0])
            .Distinct()
            .ToList();

        foreach (var feature in features)
        {
            var others = features.Where(f => f != feature).Select(f => $"{FeaturesNs}.{f}").ToArray();
            if (others.Length == 0)
            {
                continue;
            }

            var result = Types.InAssembly(ApplicationAssembly)
                .That().ResideInNamespace($"{FeaturesNs}.{feature}")
                .ShouldNot().HaveDependencyOnAny(others)
                .GetResult();

            result.FailingTypeNames.ShouldBeNull($"Feature '{feature}' references another feature");
        }
    }

    [Fact]
    public void Solution_Should_NotDeclareRepositories_When_Compiled()
    {
        var result = Types.InAssemblies(Assemblies)
            .ShouldNot().HaveNameEndingWith("Repository")
            .GetResult();

        result.FailingTypeNames.ShouldBeNull();
    }

    // ── Mediator only ─────────────────────────────────────────────────────────

    [Fact]
    public void Handlers_Should_NotDispatchOtherRequests_When_Constructed()
    {
        var offenders = HandlerConstructorParameters()
            .Where(x => x.Parameter.Name is "ISender" or "IMediator")
            .Select(x => $"{x.Handler.FullName} <- {x.Parameter.Name}")
            .ToList();

        offenders.ShouldBeEmpty("Handlers must not send other requests; move shared behavior to the domain");
    }

    // ── Direct handlers only ──────────────────────────────────────────────────

    [Fact]
    public void Handlers_Should_NotInjectOtherHandlers_When_Constructed()
    {
        var offenders = HandlerConstructorParameters()
            .Where(x => IsHandlerInterface(x.Parameter) || IsHandlerType(x.Parameter))
            .Select(x => $"{x.Handler.FullName} <- {x.Parameter.FullName}")
            .ToList();

        offenders.ShouldBeEmpty("Handlers must not inject other handlers; move shared behavior to the domain");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static IEnumerable<Type> FeatureTypes() =>
        ApplicationAssembly.GetTypes().Where(t => t.Namespace?.StartsWith(FeaturesNs, StringComparison.Ordinal) == true);

    private static IEnumerable<Type> HandlerTypes() =>
        FeatureTypes().Where(t => t is { IsClass: true, IsAbstract: false } && IsHandlerType(t));

    private static IEnumerable<(Type Handler, Type Parameter)> HandlerConstructorParameters() =>
        HandlerTypes().SelectMany(
            t => t.GetConstructors().SelectMany(c => c.GetParameters()),
            (t, p) => (t, p.ParameterType));

    // Matches IHandler<,> (direct), ICommandHandler<,> / IQueryHandler<,> (Mediator) by name.
    private static bool IsHandlerInterface(Type type) =>
        type is { IsInterface: true, IsGenericType: true } && type.Name.EndsWith("Handler`2", StringComparison.Ordinal);

    private static bool IsHandlerType(Type type) =>
        type.IsClass && type.GetInterfaces().Any(IsHandlerInterface);

    private static bool IsRequest(Type type) =>
        type.Name.EndsWith("Command", StringComparison.Ordinal) || type.Name.EndsWith("Query", StringComparison.Ordinal);

    private static bool InheritsOpenGeneric(Type type, Type openGeneric)
    {
        for (var current = type.BaseType; current is not null; current = current.BaseType)
        {
            if (current.IsGenericType && current.GetGenericTypeDefinition() == openGeneric)
            {
                return true;
            }
        }

        return false;
    }
}
