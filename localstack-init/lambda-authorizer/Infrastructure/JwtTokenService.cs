using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;

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

    public Dictionary<string, object>? DecodeToken(string token)
    {
        try
        {
            if (string.IsNullOrEmpty(token)) return null;

            var configManager = GetConfigurationManager();
            var openIdConfig = configManager.GetConfigurationAsync(CancellationToken.None).GetAwaiter().GetResult();

            var handler = new JwtSecurityTokenHandler();

            var projectId = Environment.GetEnvironmentVariable("FIREBASE_PROJECT_ID") ?? "fiapcloudgames-eaced";
            var validIssuer = $"https://securetoken.google.com/{projectId}";

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
            handler.ValidateToken(token, validationParameters, out var validatedToken);

            var jwt = validatedToken as JwtSecurityToken ?? handler.ReadJwtToken(token);

            var result = new Dictionary<string, object>();
            foreach (var claim in jwt.Claims)
            {
                // Handle repeated claim types (e.g., roles)
                if (result.TryGetValue(claim.Type, out object? existing))
                {
                    if (existing is List<string> list)
                    {
                        list.Add(claim.Value);
                    }
                    else
                    {
                        result[claim.Type] = new List<string> { existing.ToString() ?? string.Empty, claim.Value };
                    }
                }
                else
                {
                    result[claim.Type] = claim.Value;
                }
            }
            return result;
        }
        catch
        {
            return null;
        }
    }
}
