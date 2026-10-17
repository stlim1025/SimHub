using SimCenter.Application.AgentDevices;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.Tests.AgentDevices;

public class DeviceKeyFormatTests
{
    [Fact]
    public void Create_Returns43CharBase64UrlWithoutPadding()
        => Assert.Equal(
            new string('_', 42) + "8",
            DeviceKeyFormat.Create(new FixedRandom(Enumerable.Repeat((byte)0xFF, 32).ToArray())));

    private sealed class FixedRandom : IRandomSource
    {
        private readonly byte[] _bytes;

        public FixedRandom(params byte[] bytes) => _bytes = bytes;

        public byte[] GetBytes(int count) => _bytes.Take(count).ToArray();
    }
}
