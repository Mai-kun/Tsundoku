namespace MediaTracker.Server.Services.External;

[AttributeUsage(AttributeTargets.Class, Inherited = false, AllowMultiple = false)]
public sealed class MetadataSourceAttribute : Attribute
{
    public string Id { get; }
    public string Name { get; }
    public string Description { get; }
    public string[] MediaTypes { get; }
    public bool RequiresApiKey { get; set; }
    public bool IsDefault { get; set; }

    public MetadataSourceAttribute(
        string id,
        string name,
        string description,
        string[] mediaTypes)
    {
        Id = id;
        Name = name;
        Description = description;
        MediaTypes = mediaTypes;
    }
}
