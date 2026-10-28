using Xunit;

// The WebApplicationFactory-based fixtures set process-wide environment variables in their
// constructors; parallel collections race on them and randomly cross-wire hosts. The suite runs
// in ~2s, so determinism is worth more than the parallelism.
[assembly: CollectionBehavior(DisableTestParallelization = true)]
