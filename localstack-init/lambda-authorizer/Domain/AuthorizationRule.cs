namespace FiapCloudGames.Lambda.Authorizer.Domain;

public class AuthorizationRule
{
    public string Method { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public List<string> AllowedRoles { get; set; } = [];
    public bool AllowAnonymous { get; set; }
}
