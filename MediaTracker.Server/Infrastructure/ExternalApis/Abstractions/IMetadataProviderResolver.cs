namespace MediaTracker.Server.Infrastructure.ExternalApis;

public interface IMetadataProviderResolver
{
    IMetadataProvider? Resolve(string type, string? source = null);
}
