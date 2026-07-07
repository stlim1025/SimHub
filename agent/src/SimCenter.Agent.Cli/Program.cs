using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using SimCenter.Agent.Infrastructure;
using SimCenter.Agent.Infrastructure.Hosting;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddSerilog((services, config) =>
    config.ReadFrom.Configuration(builder.Configuration)
        .Enrich.FromLogContext()
        .WriteTo.Console());

builder.Services.AddAgentInfrastructure(builder.Configuration);
builder.Services.AddHostedService<TelemetryHostedService>();

var host = builder.Build();
await host.RunAsync();
