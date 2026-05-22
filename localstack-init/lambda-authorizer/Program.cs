using Amazon.Lambda.Core;
using Amazon.Lambda.Serialization.SystemTextJson;
using FiapCloudGames.Lambda.Authorizer.Infrastructure;
using System.Text.Json;

[assembly: LambdaSerializer(typeof(DefaultLambdaJsonSerializer))]

namespace FiapCloudGames.Lambda.Authorizer;

public class AuthorizerFunction
{
    private static readonly JwtTokenService JwtService = new();

    public static Dictionary<string, object> FunctionHandler(Dictionary<string, object> @event, ILambdaContext context)
    {
        context.Logger.LogLine("FunctionHandler called");
        var methodArn = GetEventString(@event, "methodArn");
        var authorizationToken =
            GetEventString(@event, "authorizationToken");

        if (string.IsNullOrEmpty(authorizationToken))
        {
            authorizationToken = ExtractAuthorizationHeader(@event);
        }
        var arnParts = methodArn.Split(':');
        var resourceParts = arnParts.Length > 5 ? arnParts[5].Split('/') : ["", "", "", ""];
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

            var userId = claims.TryGetValue("sub", out object? value) ? value.ToString() : "unknown";
            var roles = ExtractRoles(claims);

            var contextData = new Dictionary<string, object>
            {
                { "userId", userId ?? "" },
                { "roles", string.Join(",", roles) }
            };

            return BuildAllowPolicy(userId ?? "user", apiId, stage, contextData);
        }
        catch (Exception ex)
        {
            context.Logger.LogLine($"Authorization error: {ex.Message}");
            return BuildDenyPolicy("error", methodArn);
        }
    }

    private static string ExtractAuthorizationHeader(Dictionary<string, object> evt)
    {
        if (!evt.TryGetValue("headers", out var headersObj))
            return "";

        if (headersObj is JsonElement headersElement &&
            headersElement.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in headersElement.EnumerateObject())
            {
                if (prop.Name.Equals("authorization", StringComparison.OrdinalIgnoreCase) ||
                    prop.Name.Equals("authorizationToken", StringComparison.OrdinalIgnoreCase))
                {
                    return prop.Value.GetString() ?? "";
                }
            }
        }

        return "";
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

    private static string ExtractToken(string authorizationHeader)
    {
        if (string.IsNullOrEmpty(authorizationHeader))
            return string.Empty;

        const string bearer = "Bearer ";
        if (authorizationHeader.StartsWith(bearer, StringComparison.OrdinalIgnoreCase))
            return authorizationHeader[bearer.Length..];

        return authorizationHeader;
    }

    private static List<string> ExtractRoles(Dictionary<string, object> claims)
    {
        if (claims.TryGetValue("roles", out var rolesObj))
            return NormalizeRolesList(rolesObj);

        if (claims.TryGetValue("role", out var roleObj))
            return NormalizeRolesList(roleObj);

        return [];
    }

    private static List<string> NormalizeRolesList(object? rolesObj)
    {
        if (rolesObj == null)
            return [];

        if (rolesObj is System.Collections.IEnumerable enumerable && rolesObj is not string)
        {
            return [.. enumerable.Cast<object>().Select(r => r?.ToString() ?? "").Where(r => !string.IsNullOrEmpty(r))];
        }

        var rolesStr = rolesObj?.ToString() ?? "";
        return string.IsNullOrEmpty(rolesStr) ? [] : [rolesStr];
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

    private static Dictionary<string, object> BuildAllowPolicy(string principalId, string apiId, string stage, Dictionary<string, object> context)
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
