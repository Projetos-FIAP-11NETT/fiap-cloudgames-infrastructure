using Amazon.Lambda.Core;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace FiapCloudGames.Lambda.Authorizer.Infrastructure;

public class JwtTokenService : IJwtTokenService
{
    private static ConfigurationManager<OpenIdConnectConfiguration>? _configurationManager;
    private static readonly object _locker = new();

    static JwtTokenService()
    {
        // Keep JWT short claim names (sub, aud, …) so downstream code can use "sub" / custom claims.
        JwtSecurityTokenHandler.DefaultInboundClaimTypeMap.Clear();
        JwtSecurityTokenHandler.DefaultOutboundClaimTypeMap.Clear();
    }

    private static ConfigurationManager<OpenIdConnectConfiguration> GetConfigurationManager()
    {
        if (_configurationManager != null) return _configurationManager;

        lock (_locker)
        {
            if (_configurationManager != null) return _configurationManager;

            // Prefer explicit metadata address env var, otherwise try Firebase project id.
            var metadataAddress = Environment.GetEnvironmentVariable("JWKS_METADATA_ADDRESS");
            var firebaseProject = Environment.GetEnvironmentVariable("FIREBASE_PROJECT_ID");

            if (string.IsNullOrEmpty(metadataAddress) && !string.IsNullOrEmpty(firebaseProject))
            {
                metadataAddress = $"https://securetoken.google.com/{firebaseProject}/.well-known/openid-configuration";
            }

            if (string.IsNullOrEmpty(metadataAddress))
            {
                // Fallback to the project's firebase id used previously
                metadataAddress = "https://securetoken.google.com/fiapcloudgames-eaced/.well-known/openid-configuration";
            }

            _configurationManager = new ConfigurationManager<OpenIdConnectConfiguration>(
                metadataAddress,
                new OpenIdConnectConfigurationRetriever());
        }

        return _configurationManager!;
    }

    public Dictionary<string, object>? DecodeToken(string token, ILambdaContext context)
    {
        try
        {
            context.Logger.LogLine("vendo se token tah nulo");
            if (string.IsNullOrEmpty(token)) return null;

            context.Logger.LogLine("configmanager");
            var configManager = GetConfigurationManager();
            context.Logger.LogLine("openid");
            var openIdConfig = configManager.GetConfigurationAsync(CancellationToken.None).GetAwaiter().GetResult();

            context.Logger.LogLine("hadler");
            var handler = new JwtSecurityTokenHandler();

            context.Logger.LogLine("projectid");
            var projectId = Environment.GetEnvironmentVariable("FIREBASE_PROJECT_ID") ?? "fiapcloudgames-eaced";
            context.Logger.LogLine("validissuer");
            var validIssuer = $"https://securetoken.google.com/{projectId}";

            context.Logger.LogLine("validationparameters");
            var validationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = validIssuer,
                ValidateAudience = true,
                ValidAudience = projectId,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(5),
                RequireSignedTokens = true,
                IssuerSigningKeys = openIdConfig.SigningKeys
            };
            context.Logger.LogLine("validate token");
            handler.ValidateToken(token, validationParameters, out var validatedToken);

            context.Logger.LogLine("jwt");
            var jwt = validatedToken as JwtSecurityToken ?? handler.ReadJwtToken(token);

            context.Logger.LogLine("result");
            var result = new Dictionary<string, object>();
            foreach (var claim in jwt.Claims)
            {
                // Handle repeated claim types (e.g., roles)
                context.Logger.LogLine("claim");
                if (result.ContainsKey(claim.Type))
                {
                    context.Logger.LogLine("1");
                    var existing = result[claim.Type];
                    if (existing is List<string> list)
                    {
                        context.Logger.LogLine("2");
                        list.Add(claim.Value);
                    }
                    else
                    {
                        context.Logger.LogLine("3");
                        result[claim.Type] = new List<string> { existing.ToString() ?? string.Empty, claim.Value };
                    }
                }
                else
                {
                    context.Logger.LogLine("4");
                    result[claim.Type] = claim.Value;
                }
            }
            context.Logger.LogLine("sucesso fm");
            return result;
        }
        catch (Exception ex) 
        {
            context.Logger.LogLine(ex.Message);
            context.Logger.LogLine("deu ruim");
            return null;
        }
    }
}
