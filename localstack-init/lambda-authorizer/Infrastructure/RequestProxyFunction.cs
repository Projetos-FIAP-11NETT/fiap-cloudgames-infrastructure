using Amazon.Lambda.Core;

namespace FiapCloudGames.Lambda.Authorizer.Infrastructure;

public sealed class RequestProxyFunction
{
    public Dictionary<string, object> FunctionHandler(Dictionary<string, object> @event, ILambdaContext context)
    {
        // Simple gate: return 401 if no authorizer context
        if (@event == null)
            return BuildResponse(401);
        
        return BuildResponse(204);
    }

    private static Dictionary<string, object> BuildResponse(int statusCode)
    {
        return new Dictionary<string, object>
        {
            { "statusCode", statusCode },
            { "headers", new Dictionary<string, string> { { "Content-Type", "application/json" } } },
            { "body", "" },
            { "isBase64Encoded", false }
        };
    }
}
