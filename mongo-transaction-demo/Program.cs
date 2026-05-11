using MongoDB.Bson;
using MongoDB.Driver;

const string defaultConnectionString = "mongodb://127.0.0.1:27017/?replicaSet=glb-rs0";
const string defaultDatabaseName = "glb_demo";
const string defaultCollectionName = "transaction_demo";

var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "mongo-transaction-demo";
var connectionString = Environment.GetEnvironmentVariable("MONGO_CONNECTION_STRING") ?? defaultConnectionString;
var databaseName = Environment.GetEnvironmentVariable("MONGO_DATABASE") ?? defaultDatabaseName;
var collectionName = Environment.GetEnvironmentVariable("MONGO_COLLECTION") ?? defaultCollectionName;
var retryDelaySeconds = ReadIntFromEnv("TRANSACTION_RETRY_SECONDS", 5);

Console.WriteLine($"[{DateTimeOffset.UtcNow:u}] {serviceName} starting");
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

static int ReadIntFromEnv(string name, int fallback)
{
    var raw = Environment.GetEnvironmentVariable(name);
    return int.TryParse(raw, out var value) ? value : fallback;
}
