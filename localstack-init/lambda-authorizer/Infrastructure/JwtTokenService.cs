namespace FiapCloudGames.Lambda.Authorizer.Infrastructure;

public class JwtTokenService : IJwtTokenService
{
    public Dictionary<string, object>? DecodeToken(string token)
    {
        return MinimalJwtDecoder.DecodePayload(token);
    }
}
