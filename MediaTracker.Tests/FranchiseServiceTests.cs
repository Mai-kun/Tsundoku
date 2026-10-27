using FluentAssertions;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using Xunit;

namespace MediaTracker.Tests;

public class FranchiseServiceTests
{
    [Theory]
    [InlineData("Dune: Part One", "Dune")]
    [InlineData("Matrix - Reloaded", "Matrix")]
    [InlineData("Star Wars/New Hope", "Star Wars")]
    [InlineData("Season 2", null)]
    [InlineData("Part 1", null)]
    [InlineData("Abc", null)]
    [InlineData("ABCD: Test", "ABCD")]
    public void InferFranchiseName_ShouldHandlePrefixesAndSuffixes(string title, string? expected)
    {
        var service = new FranchiseService();
        service.InferFranchiseName(title).Should().Be(expected);
    }
}
