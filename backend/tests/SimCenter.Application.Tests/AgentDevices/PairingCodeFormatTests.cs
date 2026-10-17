using SimCenter.Application.AgentDevices;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.Tests.AgentDevices;

public class PairingCodeFormatTests
{
    [Fact]
    public void Create_MapsEachByteModulo32ToAlphabet()
    {
        Assert.Equal("ABCDEFGH", PairingCodeFormat.Create(new FixedRandom(0, 1, 2, 3, 4, 5, 6, 7)));
        Assert.Equal("9A9A9A9A", PairingCodeFormat.Create(new FixedRandom(31, 32, 63, 64, 95, 96, 127, 128)));
    }

    [Fact]
    public void Alphabet_Has32UniqueCharsWithoutAmbiguousOnes()
    {
        Assert.Equal(32, PairingCodeFormat.Alphabet.Length);
        Assert.Equal(32, PairingCodeFormat.Alphabet.Distinct().Count());
        Assert.DoesNotContain(PairingCodeFormat.Alphabet, c => c is '0' or 'O' or '1' or 'I');
    }

    [Fact]
    public void Display_InsertsHyphenAfterFourChars()
        => Assert.Equal("K7F2-9QXM", PairingCodeFormat.Display("K7F29QXM"));

    [Theory]
    [InlineData(" k7f2-9q xm ", "K7F29QXM")]
    [InlineData(null, "")]
    public void Normalize_UppercasesAndStripsHyphensAndWhitespace(string? input, string expected)
        => Assert.Equal(expected, PairingCodeFormat.Normalize(input));

    private sealed class FixedRandom : IRandomSource
    {
        private readonly byte[] _bytes;

        public FixedRandom(params byte[] bytes) => _bytes = bytes;

        public byte[] GetBytes(int count) => _bytes.Take(count).ToArray();
    }
}
