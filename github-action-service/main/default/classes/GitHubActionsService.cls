public with sharing class GitHubActionsService {
  private static final String GITHUB_API_URL = 'https://api.github.com';

  public class GitHubActionRequest {
    @AuraEnabled
    public String owner;
    @AuraEnabled
    public String repo;
    @AuraEnabled
    public String workflowId;
    @AuraEnabled
    public String ref;
    @AuraEnabled
    public Map<String, Object> inputs;
  }

  @AuraEnabled
  public static String triggerWorkflow(GitHubActionRequest request) {
    try {
      // Get GitHub App installation token (automatically refreshed)
      String githubToken = GitHubAppAuthService.getInstallationToken();

      String endpoint =
        'callout:GitHub_API' +
        '/repos/' +
        request.owner +
        '/' +
        request.repo +
        '/actions/workflows/' +
        request.workflowId +
        '/dispatches';

      Map<String, Object> requestBody = new Map<String, Object>{
        'ref' => request.ref,
        'inputs' => request.inputs != null
          ? request.inputs
          : new Map<String, Object>()
      };

      HttpRequest req = new HttpRequest();
      req.setEndpoint(endpoint);
      req.setMethod('POST');
      req.setHeader('Authorization', 'Bearer ' + githubToken);
      req.setHeader('Accept', 'application/vnd.github+json');
      req.setHeader('X-GitHub-Api-Version', '2022-11-28');
      req.setHeader('Content-Type', 'application/json');
      req.setBody(JSON.serialize(requestBody));
      req.setTimeout(60000);

      Http http = new Http();
      HttpResponse res = http.send(req);

      if (res.getStatusCode() == 204) {
        return 'Success: Workflow triggered';
      } else {
        throw new AuraHandledException(
          'GitHub API Error: ' + res.getStatusCode() + ' - ' + res.getBody()
        );
      }
    } catch (Exception e) {
      throw new AuraHandledException('Error: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static String listWorkflows(String owner, String repo) {
    try {
      // Get GitHub App installation token
      String githubToken = GitHubAppAuthService.getInstallationToken();

      System.debug('=== List Workflows Debug ===');
      System.debug('Owner: ' + owner);
      System.debug('Repo: ' + repo);
      System.debug(
        'Token (first 20 chars): ' +
          githubToken.substring(0, Math.min(20, githubToken.length())) +
          '...'
      );

      String endpoint =
        'callout:GitHub_API' +
        '/repos/' +
        owner +
        '/' +
        repo +
        '/actions/workflows';

      System.debug('Endpoint: ' + endpoint);

      HttpRequest req = new HttpRequest();
      req.setEndpoint(endpoint);
      req.setMethod('GET');
      req.setHeader('Authorization', 'Bearer ' + githubToken);
      req.setHeader('Accept', 'application/vnd.github+json');
      req.setHeader('X-GitHub-Api-Version', '2022-11-28');
      req.setTimeout(60000);

      Http http = new Http();
      HttpResponse res = http.send(req);

      System.debug('Response Status: ' + res.getStatusCode());
      System.debug('Response Body: ' + res.getBody());

      if (res.getStatusCode() == 200) {
        Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        System.debug(
          'Total workflows found: ' + responseData.get('total_count')
        );
        return res.getBody();
      } else {
        throw new AuraHandledException(
          'GitHub API Error: ' + res.getStatusCode() + ' - ' + res.getBody()
        );
      }
    } catch (Exception e) {
      throw new AuraHandledException('Error: ' + e.getMessage());
    }
  }
}
