using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public interface IMetadataProviderResolver
{
    IMetadataProvider? Resolve(string type, string? source = null);
}

public sealed class MetadataProviderResolver(IServiceProvider serviceProvider) : IMetadataProviderResolver
{
    public IMetadataProvider? Resolve(string type, string? source = null)
    {
        var normType = MediaMerger.NormalizeMediaType(type, source);

        if (!string.IsNullOrWhiteSpace(source))
        {
            var normSource = MediaMerger.NormalizeSourceKey(source);
            var provider = serviceProvider.GetKeyedService<IMetadataProvider>($"{normType}:{normSource}")
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(normSource)
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>($"{type}:{source}")
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(source);

            if (provider is not null)
            {
                return provider;
            }
        }

        return serviceProvider.GetKeyedService<IMetadataProvider>(normType)
               ?? serviceProvider.GetKeyedService<IMetadataProvider>(type);
    }
}
