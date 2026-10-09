// ArchitectureTests.cs — enforces the direct-handlers conventions that no dispatch pipeline
// enforces for you. See .claude/conventions/dotnet-direct-handlers.md "Do NOT".
// Copy to tests/Architecture.Tests/ArchitectureTests.cs and replace:
//   {Namespace}        root namespace (e.g. Acme.Orders)
//   {ApplicationType}  any type in the assembly holding Application/ (e.g. DependencyInjection
//                      in the 4-project layout, Program in a 1-project layout)
// Packages: xunit, Shouldly, NetArchTest.Rules. Namespace-based rules work in every solution
// layout (4-, 2- or 1-project), since namespaces do not change when assemblies collapse.

using System.Reflection;
using {Namespace}.Application.Common.Handlers;
using NetArchTest.Rules;
using Shouldly;

namespace {Namespace}.Architecture.Tests;

public sealed class ArchitectureTests
{
    private const string ApplicationNs = "{Namespace}.Application";
    private const string FeaturesNs = "{Namespace}.Application.Features";

    private static readonly Assembly ApplicationAssembly = typeof({ApplicationType}).Assembly;

    [Fact]
    public void Application_Should_NotDependOnHttp_When_Compiled()
    {
        var result = Types.InAssembly(ApplicationAssembly)
            .That().ResideInNamespace(ApplicationNs)
            .ShouldNot().HaveDependencyOnAny("FastEndpoints", "Microsoft.AspNetCore.Http")
            .GetResult();

        result.FailingTypeNames.ShouldBeNull();
    }

    [Fact]
    public void Handlers_Should_NotInjectOtherHandlers_When_Constructed()
    {
        var offenders = HandlerTypes()
            .SelectMany(t => t.GetConstructors().SelectMany(c => c.GetParameters()), (t, p) => (t, p))
            .Where(x => IsHandler(x.p.ParameterType))
            .Select(x => $"{x.t.FullName} <- {x.p.ParameterType.FullName}")
            .ToList();

        offenders.ShouldBeEmpty();
    }

    [Fact]
    public void Features_Should_NotReferenceOtherFeatures_When_Compiled()
    {
        var features = ApplicationAssembly.GetTypes()
            .Select(t => t.Namespace)
            .Where(ns => ns is not null && ns.StartsWith(FeaturesNs + ".", StringComparison.Ordinal))
            .Select(ns => ns![(FeaturesNs.Length + 1)..].Split('.')[0])
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
        var result = Types.InAssembly(ApplicationAssembly)
            .ShouldNot().HaveNameEndingWith("Repository")
            .GetResult();

        result.FailingTypeNames.ShouldBeNull();
    }

    private static IEnumerable<Type> HandlerTypes() =>
        ApplicationAssembly.GetTypes().Where(t => t is { IsClass: true, IsAbstract: false } && IsHandler(t) && !IsDecorator(t));

    private static bool IsHandler(Type type) =>
        type == typeof(IHandler<,>)
        || (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(IHandler<,>))
        || type.GetInterfaces().Any(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IHandler<,>));

    private static bool IsDecorator(Type type) =>
        type.IsGenericTypeDefinition && type.Namespace == typeof(IHandler<,>).Namespace;
}
