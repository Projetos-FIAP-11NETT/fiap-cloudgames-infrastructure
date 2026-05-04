using Amazon.Lambda.Core;
using Amazon.Lambda.Serialization.SystemTextJson;
using FiapCloudGames.Lambda.Authorizer.Infrastructure;
using System.Text.Json.Serialization;

[assembly: LambdaSerializer(typeof(DefaultLambdaJsonSerializer))]

namespace FiapCloudGames.Lambda.Authorizer;

public class AuthorizerFunction
{
    private static readonly JwtTokenService JwtService = new();
    private static readonly AuthorizationRulesService RulesService = new();

    [LambdaSerializer(typeof(SourceGeneratorLambdaJsonSerializer<AuthorizerSerializerContext>))]
    public async Task<Dictionary<string, object>> FunctionHandler(Dictionary<string, object> @event, ILambdaContext context)
    {
        try
        {
            var methodArn = @event.ContainsKey("methodArn") ? @event["methodArn"].ToString() ?? "" : "";
            var authorizationToken = @event.ContainsKey("authorizationToken") ? @event["authorizationToken"].ToString() ?? "" : "";

            // Parse methodArn: arn:aws:execute-api:region:account-id:api-id/stage/METHOD/path
            var arnParts = methodArn.Split(':');
            var resourceParts = arnParts.Length > 5 ? arnParts[5].Split('/') : new[] { "", "", "", "" };
            
            var apiId = resourceParts.Length > 0 ? resourceParts[0] : "";
            var stage = resourceParts.Length > 1 ? resourceParts[1] : "";
            var httpMethod = resourceParts.Length > 2 ? resourceParts[2] : "";
            var resourcePath = resourceParts.Length > 3 ? "/" + string.Join("/", resourceParts.Skip(3)) : "/";

            // Dev stage bypass
            if (IsDevStageBypassEnabled() && string.Equals(stage, "dev", StringComparison.OrdinalIgnoreCase))
            {
                return BuildAllowPolicy("dev-bypass", apiId, stage, methodArn, new() { { "userId", "dev-bypass" }, { "roles", "dev" } });
            }

            // Extract token from "Bearer <token>"
            var token = ExtractToken(authorizationToken);
            
            if (string.IsNullOrEmpty(token))
            {
                return BuildDenyPolicy(apiId, stage, methodArn);
            }

            // Decode token
            var claims = JwtService.DecodeToken(token);
            if (claims == null)
            {
                return BuildDenyPolicy(apiId, stage, methodArn);
            }

            var userId = claims.ContainsKey("sub") ? claims["sub"].ToString() : "unknown";
            var roles = ExtractRoles(claims);

            // Check authorization rules
            var routeKey = $"{httpMethod} {resourcePath}";
            var isAuthorized = RulesService.IsAuthorized(routeKey, roles);

            var contextData = new Dictionary<string, object>
            {
                { "userId", userId ?? "" },
                { "roles", string.Join(",", roles) }
            };

            return isAuthorized 
                ? BuildAllowPolicy(userId ?? "user", apiId, stage, methodArn, contextData)
                : BuildDenyPolicy(apiId, stage, methodArn);
        }
        catch (Exception ex)
        {
            context.Logger.LogLine($"Authorization error: {ex.Message}");
            return BuildDenyPolicy("", "", "");
        }
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
        if (!claims.ContainsKey("roles"))
            return new List<string>();

        var rolesObj = claims["roles"];
        if (rolesObj is System.Collections.IEnumerable enumerable && !(rolesObj is string))
        {
            return enumerable.Cast<object>().Select(r => r?.ToString() ?? "").Where(r => !string.IsNullOrEmpty(r)).ToList();
        }

        var rolesStr = rolesObj?.ToString() ?? "";
        return string.IsNullOrEmpty(rolesStr) ? new List<string>() : new List<string> { rolesStr };
    }

    private bool IsDevStageBypassEnabled()
    {
        return !bool.TryParse(Environment.GetEnvironmentVariable("ALLOW_DEV_STAGE_BYPASS"), out var result) || result;
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

    private Dictionary<string, object> BuildDenyPolicy(string apiId, string stage, string methodArn)
    {
        var policy = new Dictionary<string, object>
        {
            { "principalId", "user" },
            { "policyDocument", new Dictionary<string, object>
                {
                    { "Version", "2012-10-17" },
                    { "Statement", new List<Dictionary<string, object>>
                        {
                            new()
                            {
                                { "Action", "execute-api:Invoke" },
                                { "Effect", "Deny" },
                                { "Resource", $"arn:aws:execute-api:*:*:{apiId}/{stage}/*/*" }
                            }
                        }
                    }
                }
            }
        };
        return policy;
    }
}

[JsonSerializable(typeof(Dictionary<string, object>))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
public partial class AuthorizerSerializerContext : JsonSerializerContext
{
}
