/**
 * @description Service for dispatching GitHub repository_dispatch events
 * Provides a framework for sending structured events to GitHub Actions
 */
public with sharing class GitHubDispatchService {
  private String owner;
  private String repo;

  /**
   * @description Constructor with default repository
   */
  public GitHubDispatchService() {
    // Default values - can be overridden
    this.owner = 'Gforce-Innovation-Kft';
    this.repo = 'sf-develop-demo';
  }

  /**
   * @description Constructor with custom repository
   */
  public GitHubDispatchService(String owner, String repo) {
    this.owner = owner;
    this.repo = repo;
  }

  /**
   * @description Dispatch an event to GitHub
   * @param event The GitHubDispatchEvent to send
   * @return Boolean true if successful
   */
  public Boolean dispatch(GitHubDispatchEvent event) {
    // Validate event
    event.validate();

    // Get installation token
    String token = GitHubAppAuthService.getInstallationToken();

    // Build request
    HttpRequest req = buildRequest(token, event);

    // Send request
    Http http = new Http();
    HttpResponse res = http.send(req);

    // Log the dispatch
    logDispatch(event, res);

    // Check response
    if (res.getStatusCode() == 204) {
      System.debug('✅ Dispatch successful: ' + event.getEventType());
      return true;
    } else {
      String errorMsg =
        'GitHub dispatch failed: ' +
        res.getStatusCode() +
        ' - ' +
        res.getBody();
      System.debug('❌ ' + errorMsg);
      throw new GitHubDispatchEvent.GitHubDispatchException(errorMsg);
    }
  }

  /**
   * @description Dispatch multiple events in sequence
   * @param events List of events to dispatch
   * @return Map of event type to success status
   */
  public Map<String, Boolean> dispatchBatch(List<GitHubDispatchEvent> events) {
    Map<String, Boolean> results = new Map<String, Boolean>();

    for (GitHubDispatchEvent event : events) {
      try {
        Boolean success = dispatch(event);
        results.put(event.getEventType(), success);
      } catch (Exception e) {
        System.debug(
          '❌ Failed to dispatch ' +
            event.getEventType() +
            ': ' +
            e.getMessage()
        );
        results.put(event.getEventType(), false);
      }
    }

    return results;
  }

  /**
   * @description Build HTTP request for dispatch
   */
  private HttpRequest buildRequest(String token, GitHubDispatchEvent event) {
    String endpoint =
      'callout:GitHub_API/repos/' +
      owner +
      '/' +
      repo +
      '/dispatches';

    Map<String, Object> requestBody = new Map<String, Object>{
      'event_type' => event.getEventType(),
      'client_payload' => event.buildPayload()
    };

    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('POST');
    req.setHeader('Authorization', 'Bearer ' + token);
    req.setHeader('Accept', 'application/vnd.github+json');
    req.setHeader('X-GitHub-Api-Version', '2022-11-28');
    req.setHeader('Content-Type', 'application/json');
    req.setBody(JSON.serialize(requestBody));
    req.setTimeout(60000);

    return req;
  }

  /**
   * @description Log the dispatch for debugging/auditing
   */
  private void logDispatch(GitHubDispatchEvent event, HttpResponse res) {
    System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    System.debug('📤 GitHub Dispatch Event');
    System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    System.debug('Event Type: ' + event.getEventType());
    System.debug('Repository: ' + owner + '/' + repo);
    System.debug('Response Code: ' + res.getStatusCode());
    System.debug('Metadata: ' + JSON.serialize(event.getMetadata()));
    System.debug('Payload: ' + JSON.serializePretty(event.buildPayload()));
    System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /**
   * @description Set custom repository
   */
  public GitHubDispatchService setRepository(String owner, String repo) {
    this.owner = owner;
    this.repo = repo;
    return this;
  }
}
