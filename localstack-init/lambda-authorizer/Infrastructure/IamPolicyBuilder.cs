namespace FiapCloudGames.Lambda.Authorizer.Infrastructure;

public interface IIamPolicyBuilder
{
    Dictionary<string, object> BuildPolicy(string principalId, bool isAuthorized, string apiId, string stage, string resource);
}

public class IamPolicyBuilder : IIamPolicyBuilder
{
    public Dictionary<string, object> BuildPolicy(string principalId, bool isAuthorized, string apiId, string stage, string resource)
    {
        var effect = isAuthorized ? "Allow" : "Deny";
        var arn = $"arn:aws:execute-api:us-east-1:123456789012:{apiId}/{stage}/*";

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
                                { "Effect", effect },
                                { "Resource", arn }
                            }
                        }
                    }
                }
            }
        };

        return policy;
    }
}
