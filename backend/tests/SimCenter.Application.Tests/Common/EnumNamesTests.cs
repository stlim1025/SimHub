using SimCenter.Application.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Common;

public class EnumNamesTests
{
    [Theory]
    [InlineData("Wheel", true, ControllerType.Wheel)]
    [InlineData("gamepad", true, ControllerType.Gamepad)]
    [InlineData("WHEEL", true, ControllerType.Wheel)]
    [InlineData("Joystick", false, ControllerType.Gamepad)]
    [InlineData("1", false, ControllerType.Gamepad)]
    [InlineData("Gamepad,Wheel", false, ControllerType.Gamepad)]
    [InlineData(" Wheel", false, ControllerType.Gamepad)]
    [InlineData("", false, ControllerType.Gamepad)]
    [InlineData(null, false, ControllerType.Gamepad)]
    public void TryParse_AcceptsNamesOnly_IgnoringCase(string? input, bool expectedOk, ControllerType expected)
    {
        var ok = EnumNames.TryParse<ControllerType>(input, out var parsed);

        Assert.Equal(expectedOk, ok);
        Assert.Equal(expected, parsed);
    }
}
