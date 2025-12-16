// ============================================================================
// SIMPLE EXAMPLE: Trigger GitHub Action from Salesforce
// ============================================================================
// Copy and paste this into Developer Console → Debug → Open Execute Anonymous Window
// ============================================================================

// Get your GitHub token
String token = GitHubAppAuthService.getInstallationToken();

// Create your payload (customize this!)
Map<String, Object> payload = new Map<String, Object>{
    'event_type' => 'salesforce_event',
    'client_payload' => new Map<String, Object>{
        'message' => 'Hello from Salesforce!',
        'recordId' => '0015000000ABC123',
        'action' => 'test'
    }
};

// Send to GitHub
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:GitHub_API/repos/gforceinnovation/sf-develop-demo/dispatches');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + token);
req.setHeader('Accept', 'application/vnd.github+json');
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(payload));

HttpResponse res = new Http().send(req);

// Check result
if (res.getStatusCode() == 204) {
    System.debug('✅ SUCCESS! Check GitHub Actions tab');
} else {
    System.debug('❌ Error: ' + res.getStatusCode() + ' - ' + res.getBody());
}

