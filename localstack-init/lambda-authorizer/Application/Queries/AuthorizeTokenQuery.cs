namespace FiapCloudGames.Lambda.Authorizer.Application.Queries;

public class AuthorizeTokenQuery
{
    public string Token { get; set; } = string.Empty;
    public string HttpMethod { get; set; } = string.Empty;
    public string ResourcePath { get; set; } = string.Empty;
    public string ApiId { get; set; } = string.Empty;
    public string Stage { get; set; } = string.Empty;
}
