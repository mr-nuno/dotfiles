// VogenEfCoreConverters.cs — EF Core value converters for every Vogen ID, generated in
// Infrastructure so Domain keeps no EF Core dependency.
// See .claude/docs/domain-entities.md "Strongly Typed IDs". Copy to
// src/{Infrastructure}/Persistence/VogenEfCoreConverters.cs and add one attribute per ID.
// Register them once in AppDbContext:
//
//     protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder) =>
//         configurationBuilder.RegisterAllInVogenEfCoreConverters();

using Vogen;

namespace {Namespace}.Infrastructure.Persistence;

[EfCoreConverter<{Entity}Id>]
internal sealed partial class VogenEfCoreConverters;
