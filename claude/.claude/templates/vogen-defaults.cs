// VogenDefaults.cs — assembly-wide defaults for the Vogen source generator.
// See .claude/docs/domain-entities.md "Strongly Typed IDs". Copy to
// src/{Domain}/Common/VogenDefaults.cs. With these defaults every ID is a one-liner:
//
//     [ValueObject]
//     public readonly partial struct OrderId;
//
// That generates From(Guid), FromNewGuid(), Value, equality, a flat System.Text.Json
// converter and a TypeConverter (route/query binding). Int-backed IDs override the
// underlying type per ID: [ValueObject<int>] public readonly partial struct TicketId;

using Vogen;

[assembly: VogenDefaults(
    underlyingType: typeof(Guid),
    conversions: Conversions.SystemTextJson | Conversions.TypeConverter,
    customizations: Customizations.AddFactoryMethodForGuids)]
