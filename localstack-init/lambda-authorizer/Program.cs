using Amazon.Lambda.Core;
using Amazon.Lambda.Serialization.SystemTextJson;
using FiapCloudGames.Lambda.Authorizer.Infrastructure;
using System.Text.Json;
using System.Text.Json.Serialization;

[assembly: LambdaSerializer(typeof(DefaultLambdaJsonSerializer))]

namespace FiapCloudGames.Lambda.Authorizer;

public class AuthorizerFunction
{
    private static readonly JwtTokenService JwtService = new();

    [LambdaSerializer(typeof(SourceGeneratorLambdaJsonSerializer<AuthorizerSerializerContext>))]
    public Dictionary<string, object> FunctionHandler(Dictionary<string, object> @event, ILambdaContext context)
    {
        var methodArn = GetEventString(@event, "methodArn");
        var authorizationToken = GetEventString(@event, "authorizationToken");
        var arnParts = methodArn.Split(':');
        var resourceParts = arnParts.Length > 5 ? arnParts[5].Split('/') : new[] { "", "", "", "" };
        var apiId = resourceParts.Length > 0 ? resourceParts[0] : "";
        var stage = resourceParts.Length > 1 ? resourceParts[1] : "";

        try
        {
            var token = ExtractToken(authorizationToken);

            if (string.IsNullOrEmpty(token))
            {
                context.Logger.LogLine("Authorization refused: missing or empty Bearer token.");
                return BuildDenyPolicy("unauthorized-user", methodArn);
            }

            var claims = JwtService.DecodeToken(token);
            if (claims == null)
            {
                context.Logger.LogLine("Authorization refused: Firebase token validation failed.");
                return BuildDenyPolicy("unauthorized-user", methodArn);
            }

            var userId = claims.ContainsKey("sub") ? claims["sub"].ToString() : "unknown";
            var roles = ExtractRoles(claims);

            var contextData = new Dictionary<string, object>
            {
                { "userId", userId ?? "" },
                { "roles", string.Join(",", roles) }
            };

            return BuildAllowPolicy(userId ?? "user", apiId, stage, methodArn, contextData);
        }
        catch (Exception ex)
        {
            context.Logger.LogLine($"Authorization error: {ex.Message}");
            return BuildDenyPolicy("error", methodArn);
        }
    }

    private static string GetEventString(Dictionary<string, object> evt, string key)
    {
        if (!evt.TryGetValue(key, out var value) || value == null)
            return "";

        return value switch
        {
            string s => s,
            JsonElement je when je.ValueKind == JsonValueKind.String => je.GetString() ?? "",
            JsonElement je => je.ToString(),
            _ => value.ToString() ?? ""
        };
    }

    private string ExtractToken(string authorizationHeader)
    {
        if (string.IsNullOrEmpty(authorizationHeader))
            return string.Empty;

        const string bearer = "Bearer ";
        if (authorizationHeader.StartsWith(bearer, StringComparison.OrdinalIgnoreCase))
            return authorizationHeader.Substring(bearer.Length);

        return authorizationHeader;
    }

    private List<string> ExtractRoles(Dictionary<string, object> claims)
    {
        if (claims.TryGetValue("roles", out var rolesObj))
            return NormalizeRolesList(rolesObj);

        if (claims.TryGetValue("role", out var roleObj))
            return NormalizeRolesList(roleObj);

        return new List<string>();
    }

    private static List<string> NormalizeRolesList(object? rolesObj)
    {
        if (rolesObj == null)
            return new List<string>();

        if (rolesObj is System.Collections.IEnumerable enumerable && !(rolesObj is string))
        {
            return enumerable.Cast<object>().Select(r => r?.ToString() ?? "").Where(r => !string.IsNullOrEmpty(r)).ToList();
        }

        var rolesStr = rolesObj?.ToString() ?? "";
        return string.IsNullOrEmpty(rolesStr) ? new List<string>() : new List<string> { rolesStr };
    }

    private static Dictionary<string, object> BuildDenyPolicy(string principalId, string methodArn)
    {
        var resource = string.IsNullOrEmpty(methodArn) ? "*" : methodArn;
        return new Dictionary<string, object>
        {
            { "principalId", principalId },
            { "policyDocument", new Dictionary<string, object>
                {
                    { "Version", "2012-10-17" },
                    { "Statement", new List<Dictionary<string, object>>
                        {
                            new()
                            {
                                { "Action", "execute-api:Invoke" },
                                { "Effect", "Deny" },
                                { "Resource", resource }
                            }
                        }
                    }
                }
            }
        };
    }

    private Dictionary<string, object> BuildAllowPolicy(string principalId, string apiId, string stage, string methodArn, Dictionary<string, object> context)
    {
        var policy = new Dictionary<string, object>
        {
            { "principalId", principalId },
            { "policyDocument", new Dictionary<string, object>
                {
                    { "Version", "2012-10-17" },
                    { "Statement", new List<Dictionary<string, object>>
                        {
                            new()
                            {
                                { "Action", "execute-api:Invoke" },
                                { "Effect", "Allow" },
                                { "Resource", $"arn:aws:execute-api:*:*:{apiId}/{stage}/*/*" }
                            }
                        }
                    }
                }
            },
            { "context", context }
        };
        return policy;
    }

}

[JsonSerializable(typeof(Dictionary<string, object>))]
[JsonSerializable(typeof(List<Dictionary<string, object>>))]
[JsonSerializable(typeof(List<object>))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
public partial class AuthorizerSerializerContext : JsonSerializerContext
{
}
