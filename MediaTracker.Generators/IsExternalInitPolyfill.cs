// Polyfill for init-only property support on netstandard2.0.
namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit { }
}
