namespace MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

public interface IMetadataProviderResolver
{
    IMetadataProvider? Resolve(string type, string? source = null);
}
