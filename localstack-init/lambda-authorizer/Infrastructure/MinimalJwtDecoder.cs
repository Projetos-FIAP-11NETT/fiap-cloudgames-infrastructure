using System.Text;
using System.Text.Json;

namespace FiapCloudGames.Lambda.Authorizer.Infrastructure;

/// <summary>
/// Ultra-lightweight JWT decoder that only decodes payload without signature validation.
/// Replaces System.IdentityModel.Tokens.Jwt to reduce cold start time and package size.
/// </summary>
public static class MinimalJwtDecoder
{
    public static Dictionary<string, object>? DecodePayload(string token)
    {
        try
        {
            if (string.IsNullOrEmpty(token))
                return null;

            // JWT format: header.payload.signature
            var parts = token.Split('.');
            if (parts.Length < 2)
                return null;

            // Base64 decode payload (add padding if needed)
            var payloadBase64 = parts[1];
            var padding = 4 - (payloadBase64.Length % 4);
            if (padding > 0 && padding < 4)
                payloadBase64 += new string('=', padding);

            var payloadJson = Encoding.UTF8.GetString(Convert.FromBase64String(payloadBase64));
            var payload = JsonSerializer.Deserialize<Dictionary<string, object>>(payloadJson)
                ?? [];

            return payload;
        }
        catch
        {
            return null;
        }
    }
}
