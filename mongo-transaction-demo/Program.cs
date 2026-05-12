using System.Text.Json;
using MongoDB.Bson;
using MongoDB.Driver;

const string defaultConnectionString = "mongodb://127.0.0.1:27017/?replicaSet=glb-rs0";
const string defaultDatabaseName = "glb_demo";
const string defaultCollectionName = "transaction_demo";
const int defaultRetryDelaySeconds = 5;

var configPath = Environment.GetEnvironmentVariable("SERVICE_CONFIG_PATH");
var fileConfig = LoadServiceConfig(configPath);
var mongoConfig = fileConfig.Mongo;

var serviceName = ReadStringFromEnv("SERVICE_NAME", fileConfig.ServiceName ?? "mongo-transaction-demo");
var connectionString = ReadStringFromEnv("MONGO_CONNECTION_STRING", mongoConfig.ConnectionString ?? defaultConnectionString);
var databaseName = ReadStringFromEnv("MONGO_DATABASE", mongoConfig.Database ?? defaultDatabaseName);
var collectionName = ReadStringFromEnv("MONGO_COLLECTION", mongoConfig.Collection ?? defaultCollectionName);
var retryDelaySeconds = ReadIntFromEnv("TRANSACTION_RETRY_SECONDS", mongoConfig.RetrySeconds ?? defaultRetryDelaySeconds);

Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] {serviceName} starting");
if (!string.IsNullOrWhiteSpace(configPath))
{
    Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] Loading config from: {configPath}");
}
Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] Using MongoDB connection string: {connectionString}");

var settings = MongoClientSettings.FromConnectionString(connectionString);
settings.ServerSelectionTimeout = TimeSpan.FromSeconds(5);
var client = new MongoClient(settings);
var collection = client.GetDatabase(databaseName).GetCollection<BsonDocument>(collectionName);

while (true)
{
    try
    {
        using var session = await client.StartSessionAsync();
        session.StartTransaction();

        var document = new BsonDocument
        {
            { "service", serviceName },
            { "machine", Environment.MachineName },
            { "createdAtUtc", DateTime.UtcNow },
            { "message", "Transaction committed from the bundled .NET 8 demo service." }
        };

        await collection.InsertOneAsync(session, document);
        await session.CommitTransactionAsync();

        Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] Transaction committed successfully to {databaseName}.{collectionName}");
        break;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] Transaction attempt failed: {ex.Message}");
        Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] Retrying in {retryDelaySeconds} seconds...");
        await Task.Delay(TimeSpan.FromSeconds(retryDelaySeconds));
    }
}

await Task.Delay(Timeout.InfiniteTimeSpan);

static ServiceConfig LoadServiceConfig(string? configPath)
{
    if (string.IsNullOrWhiteSpace(configPath))
    {
        return new ServiceConfig();
    }

    if (!File.Exists(configPath))
    {
        Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] Config file not found at {configPath}; using defaults and environment variables.");
        return new ServiceConfig();
    }

    try
    {
        var json = File.ReadAllText(configPath);
        var jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        };
        return JsonSerializer.Deserialize<ServiceConfig>(json, jsonOptions) ?? new ServiceConfig();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] Failed to load config file {configPath}: {ex.Message}");
        return new ServiceConfig();
    }
}

static string ReadStringFromEnv(string name, string fallback)
{
    var raw = Environment.GetEnvironmentVariable(name);
    return string.IsNullOrWhiteSpace(raw) ? fallback : raw;
}

static int ReadIntFromEnv(string name, int fallback)
{
    var raw = Environment.GetEnvironmentVariable(name);
    return int.TryParse(raw, out var value) ? value : fallback;
}

sealed class ServiceConfig
{
    public string? ServiceName { get; init; }
    public MongoConfig Mongo { get; init; } = new();
}

sealed class MongoConfig
{
    public string? ConnectionString { get; init; }
    public string? Database { get; init; }
    public string? Collection { get; init; }
    public int? RetrySeconds { get; init; }
}
