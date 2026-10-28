using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using System.Threading;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Text;

namespace MediaTracker.Generators;

/// <summary>
/// Source generator that replaces reflection-based discovery of <see cref="IMetadataProvider"/>
/// implementations and FluentValidation validators with compile-time, type-safe registrations.
///
/// It finds every non-abstract class implementing <c>IMetadataProvider</c> and generates a partial
/// addition to <see cref="MetadataSourceRegistry"/> containing all <c>Provider.Source</c> values and
/// explicit <c>AddTransient&lt;IMetadataProvider, T&gt;</c> / <c>AddKeyedTransient&lt;IMetadataProvider, T&gt;(key)</c>
/// calls. It also finds every non-abstract class implementing <c>IValidator&lt;T&gt;</c> and generates
/// <c>AddGeneratedValidators</c> with explicit <c>AddScoped&lt;IValidator&lt;T&gt;, TValidator&gt;</c> calls.
/// </summary>
[Generator]
public sealed class RegistrationGenerator : IIncrementalGenerator
{
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        // Collect all (class declaration, compilation) pairs.
        var classCompilationPairs = context.SyntaxProvider
            .CreateSyntaxProvider(
                predicate: static (s, _) => s is ClassDeclarationSyntax,
                transform: static (ctx, _) => (ClassDeclarationSyntax)ctx.Node)
            .Where(static m => m is not null)
            .Combine(context.CompilationProvider)
            .Collect();

        context.RegisterSourceOutput(classCompilationPairs, static (spc, pairs) =>
        {
            if (pairs.IsDefaultOrEmpty) return;

            // Use the compilation from the first pair (all pairs share the same compilation).
            var compilation = pairs[0].Right;

            // --- Metadata providers ---
            var providerInfos = new List<ProviderInfo>();
            foreach (var (classDecl, _) in pairs)
            {
                var info = TryGetProviderInfo(classDecl, compilation);
                if (info is not null) providerInfos.Add(info);
            }

            if (providerInfos.Count > 0)
            {
                spc.AddSource("MetadataSourceRegistry.generated.cs", GenerateRegistry(providerInfos.ToImmutableArray()));
            }

            // --- Validators ---
            var validatorInfos = new List<ValidatorInfo>();
            foreach (var (classDecl, _) in pairs)
            {
                foreach (var info in TryGetValidatorInfos(classDecl, compilation))
                {
                    validatorInfos.Add(info);
                }
            }

            if (validatorInfos.Count > 0)
            {
                spc.AddSource("FeatureRegistration.Validators.generated.cs", GenerateValidators(validatorInfos.ToImmutableArray()));
            }
        });
    }

    private static ProviderInfo? TryGetProviderInfo(
        ClassDeclarationSyntax classDecl,
        Compilation compilation)
    {
        var semanticModel = compilation.GetSemanticModel(classDecl.SyntaxTree);
        var typeSymbol = semanticModel.GetDeclaredSymbol(classDecl);
        if (typeSymbol is null || typeSymbol.IsAbstract) return null;

        var providerInterface = compilation.GetTypeByMetadataName("MediaTracker.Server.Infrastructure.ExternalApis.IMetadataProvider");
        if (providerInterface is null) return null;

        // Walk the base type chain to find IMetadataProvider (providers inherit it via MetadataProviderBase).
        var current = typeSymbol;
        while (current is not null)
        {
            foreach (var iface in current.Interfaces)
            {
                if (SymbolEqualityComparer.Default.Equals(iface, providerInterface))
                {
                    return new ProviderInfo(typeSymbol.Name, typeSymbol.ContainingNamespace.ToDisplayString());
                }
            }
            current = current.BaseType;
        }

        return null;
    }

    private static IEnumerable<ValidatorInfo> TryGetValidatorInfos(
        ClassDeclarationSyntax classDecl,
        Compilation compilation)
    {
        var semanticModel = compilation.GetSemanticModel(classDecl.SyntaxTree);
        var typeSymbol = semanticModel.GetDeclaredSymbol(classDecl);
        if (typeSymbol is null || typeSymbol.IsAbstract) yield break;

        var validatorInterface = compilation.GetTypeByMetadataName("FluentValidation.IValidator`1");
        if (validatorInterface is null) yield break;

        // Walk the base type chain to find IValidator<T> (validators inherit it via AbstractValidator<T>).
        var current = typeSymbol;
        while (current is not null)
        {
            foreach (var iface in current.Interfaces)
            {
                if (iface.IsGenericType &&
                    SymbolEqualityComparer.Default.Equals(iface.ConstructedFrom, validatorInterface))
                {
                    var targetType = iface.TypeArguments[0];
                    yield return new ValidatorInfo(
                        typeSymbol.Name,
                        typeSymbol.ContainingNamespace.ToDisplayString(),
                        targetType.Name,
                        targetType.ContainingNamespace.ToDisplayString());
                }
            }
            current = current.BaseType;
        }
    }

    private static string GenerateRegistry(ImmutableArray<ProviderInfo> sources)
    {
        var sb = new StringBuilder();
        sb.AppendLine("// <auto-generated/>");
        sb.AppendLine("using MediaTracker.Server.Infrastructure.ExternalApis;");
        sb.AppendLine("using Microsoft.Extensions.DependencyInjection;");
        sb.AppendLine();
        sb.AppendLine("namespace MediaTracker.Server.Infrastructure.ExternalApis;");
        sb.AppendLine();
        sb.AppendLine("/// <summary>");
        sb.AppendLine("/// Auto-generated by MediaTracker.Generators. Do not edit by hand.");
        sb.AppendLine("/// Lists every <see cref=\"IMetadataProvider\">provider</see>'s <c>Source</c> descriptor and");
        sb.AppendLine("/// registers each provider with the DI container without reflection.");
        sb.AppendLine("/// </summary>");
        sb.AppendLine("public static partial class MetadataSourceRegistry");
        sb.AppendLine("{");
        sb.AppendLine("    private static readonly List<MetadataSourceDescriptor> _generatedSources = new();");
        sb.AppendLine();
        sb.AppendLine("    static MetadataSourceRegistry()");
        sb.AppendLine("    {");

        foreach (var s in sources)
        {
            sb.Append("        _generatedSources.Add(");
            sb.Append(s.TypeName);
            sb.AppendLine(".Source);");
        }

        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine("    /// <summary>All discovered provider descriptors (populated at module initialization).</summary>");
        sb.AppendLine("    public static IReadOnlyList<MetadataSourceDescriptor> GeneratedSources => _generatedSources;");
        sb.AppendLine();
        sb.AppendLine("    /// <summary>");
        sb.AppendLine("    /// Registers every discovered provider with the container. Called from");
        sb.AppendLine("    /// <see cref=\"MetadataServiceExtensions.AddAllMetadataProviders\"/> in place of reflection.");
        sb.AppendLine("    /// </summary>");
        sb.AppendLine("    public static IServiceCollection AddGeneratedProviders(IServiceCollection services)");
        sb.AppendLine("    {");
        sb.AppendLine("        // Keyed and unkeyed provider registrations.");

        foreach (var s in sources)
        {
            sb.Append("        // ");
            sb.AppendLine(s.TypeName);
            sb.Append("        services.AddTransient<IMetadataProvider, ");
            sb.Append(s.Namespace);
            sb.Append('.');
            sb.Append(s.TypeName);
            sb.AppendLine(">();");
            sb.Append("        services.AddKeyedTransient<IMetadataProvider, ");
            sb.Append(s.Namespace);
            sb.Append('.');
            sb.Append(s.TypeName);
            sb.AppendLine(">(" + s.TypeName + ".Source.Id);");

            sb.Append("        foreach (var mediaType in ");
            sb.Append(s.TypeName);
            sb.AppendLine(".Source.MediaTypes)");
            sb.AppendLine("        {");
            sb.Append("            services.AddKeyedTransient<IMetadataProvider, ");
            sb.Append(s.Namespace);
            sb.Append('.');
            sb.Append(s.TypeName);
            sb.AppendLine(">($\"{mediaType}:" + s.TypeName + ".Source.Id\");");
            sb.Append("            if (");
            sb.Append(s.TypeName);
            sb.AppendLine(".Source.IsDefault)");
            sb.AppendLine("            {");
            sb.Append("                services.AddKeyedTransient<IMetadataProvider, ");
            sb.Append(s.Namespace);
            sb.Append('.');
            sb.Append(s.TypeName);
            sb.AppendLine(">(mediaType);");
            sb.AppendLine("            }");
            sb.AppendLine("        }");
        }

        sb.AppendLine("        return services;");
        sb.AppendLine("    }");
        sb.AppendLine("}");

        return sb.ToString();
    }

    private static string GenerateValidators(ImmutableArray<ValidatorInfo> validators)
    {
        var sb = new StringBuilder();
        sb.AppendLine("// <auto-generated/>");
        sb.AppendLine("using FluentValidation;");
        sb.AppendLine("using Microsoft.Extensions.DependencyInjection;");
        sb.AppendLine();
        sb.AppendLine("namespace MediaTracker.Server.Features;");
        sb.AppendLine();
        sb.AppendLine("/// <summary>");
        sb.AppendLine("/// Auto-generated by MediaTracker.Generators. Do not edit by hand.");
        sb.AppendLine("/// Registers every FluentValidation validator found in the assembly without reflection.");
        sb.AppendLine("/// </summary>");
        sb.AppendLine("public static partial class FeatureRegistration");
        sb.AppendLine("{");
        sb.AppendLine("    /// <summary>");
        sb.AppendLine("    /// Registers every discovered validator as <c>AddScoped&lt;IValidator&lt;T&gt;, TValidator&gt;</c>.");
        sb.AppendLine("    /// </summary>");
        sb.AppendLine("    public static IServiceCollection AddGeneratedValidators(this IServiceCollection services)");
        sb.AppendLine("    {");

        foreach (var v in validators)
        {
            sb.Append("        services.AddScoped<IValidator<");
            sb.Append(v.TargetNamespace);
            sb.Append('.');
            sb.Append(v.TargetType);
            sb.Append(">, ");
            sb.Append(v.Namespace);
            sb.Append('.');
            sb.Append(v.ValidatorName);
            sb.AppendLine(">();");
        }

        sb.AppendLine("        return services;");
        sb.AppendLine("    }");
        sb.AppendLine("}");

        return sb.ToString();
    }

    private sealed class ProviderInfo(string typeName, string @namespace)
    {
        public string TypeName { get; } = typeName;
        public string Namespace { get; } = @namespace;
    }

    private sealed class ValidatorInfo(string validatorName, string @namespace, string targetType, string targetNamespace)
    {
        public string ValidatorName { get; } = validatorName;
        public string Namespace { get; } = @namespace;
        public string TargetType { get; } = targetType;
        public string TargetNamespace { get; } = targetNamespace;
    }
}
