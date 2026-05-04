namespace FiapCloudGames.Lambda.Authorizer.Domain;

public class AuthorizationResult
{
    public string PrincipalId { get; set; } = string.Empty;
    public bool IsAuthorized { get; set; }
    public Dictionary<string, object>? Context { get; set; }
    public List<string>? Roles { get; set; }
}
