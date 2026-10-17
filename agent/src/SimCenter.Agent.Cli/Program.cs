using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using SimCenter.Agent.Infrastructure;
using SimCenter.Agent.Infrastructure.Hosting;
using SimCenter.Agent.Infrastructure.Pairing;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddSerilog((services, config) =>
    config.ReadFrom.Configuration(builder.Configuration)
        .Enrich.FromLogContext()
        .WriteTo.Console());

builder.Services.AddAgentInfrastructure(builder.Configuration);
builder.Services.AddHostedService<TelemetryHostedService>();

using var host = builder.Build();

// `pair <코드>`: 호스트(UDP 수신·업로드)를 시작하지 않고, 서비스 공급자에서 연결 클라이언트만 꺼내 한 번 실행한 뒤 종료한다.
if (PairCommand.IsPairInvocation(args))
{
    using var cancellation = new CancellationTokenSource();
    Console.CancelKeyPress += (_, e) =>
    {
        e.Cancel = true; // 즉시 죽이지 않고 진행 중인 요청을 취소로 마무리한다.
        cancellation.Cancel();
    };

    var pairingClient = host.Services.GetRequiredService<IAgentPairingClient>();
    return await PairCommand.RunAsync(args, pairingClient, Environment.MachineName, Console.Out, cancellation.Token);
}

await host.RunAsync();
return 0;
