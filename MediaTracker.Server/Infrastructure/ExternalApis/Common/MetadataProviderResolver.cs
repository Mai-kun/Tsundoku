using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

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
                if (!string.IsNullOrWhiteSpace(normType) && normType != "all" &&
                    !provider.MediaTypes.Contains(normType, StringComparer.OrdinalIgnoreCase))
                {
                    return null;
                }

                return provider;
            }
        }

        return serviceProvider.GetKeyedService<IMetadataProvider>(normType)
               ?? serviceProvider.GetKeyedService<IMetadataProvider>(type);
    }
}
