namespace FiapCloudGames.Lambda.Authorizer.Infrastructure;

public interface IJwtTokenService
{
    Dictionary<string, object>? DecodeToken(string token);
}
