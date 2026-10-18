using System.Text.Json;
using SimCenter.Application.Common;

namespace SimCenter.Application.Tests.Common;

/// <summary>jsonb에 그대로 저장할 원문(D-49): 객체·크기 한도·jsonb가 거부하는 문자열 확인.</summary>
public class JsonbTextTests
{
    private static JsonElement Parse(string json) => JsonDocument.Parse(json).RootElement.Clone();

    [Fact]
    public void Object_IsCapturedVerbatim()
    {
        const string json = "{\"setup\":{\"frontWing\":5,\"brakeBias\":56.5},\"events\":[{\"code\":\"FTLP\",\"t\":12.3}],\"name\":\"한글\"}";

        var raw = JsonbText.TryCaptureObject(Parse(json), 1024, out var reason);

        Assert.Equal(json, raw);
        Assert.Null(reason);
    }

    [Theory]
    [InlineData("[1,2]")]
    [InlineData("\"text\"")]
    [InlineData("42")]
    public void NonObject_IsRejected(string json)
    {
        Assert.Null(JsonbText.TryCaptureObject(Parse(json), 1024, out var reason));
        Assert.Contains("객체", reason);
    }

    [Fact]
    public void OverSizeLimit_IsRejected()
    {
        var json = $"{{\"a\":\"{new string('x', 100)}\"}}";

        Assert.Null(JsonbText.TryCaptureObject(Parse(json), 50, out var reason));
        Assert.Contains("크기", reason);
        Assert.NotNull(JsonbText.TryCaptureObject(Parse(json), 200, out _));
    }

    [Theory]
    [InlineData("{\"a\":\"x\\u0000y\"}")]          // NUL 문자열(jsonb 거부)
    [InlineData("{\"a\\u0000\":1}")]               // NUL 속성 이름
    [InlineData("{\"a\":[{\"b\":\"\\u0000\"}]}")]  // 깊은 곳의 NUL
    [InlineData("{\"a\":\"\\ud800\"}")]            // 짝 없는 서로게이트
    public void UnstorableStrings_AreRejected(string json)
    {
        Assert.Null(JsonbText.TryCaptureObject(Parse(json), 1024, out var reason));
        Assert.Contains("jsonb", reason);
    }
}
