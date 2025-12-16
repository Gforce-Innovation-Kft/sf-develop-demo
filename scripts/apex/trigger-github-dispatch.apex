// ============================================================================
// Anonymous Apex: Trigger GitHub repository_dispatch Event
// ============================================================================
// Purpose: Send a repository_dispatch event to GitHub using JWT authentication
// Usage: Execute this in Developer Console or VS Code Anonymous Apex window
// ============================================================================

// STEP 1: Get Installation Token (uses your JWT authentication)
String installationToken = GitHubAppAuthService.getInstallationToken();

System.debug('✅ Token retrieved: ' + installationToken.substring(0, 10) + '...');

// STEP 2: Prepare the repository_dispatch payload
Map<String, Object> clientPayload = new Map<String, Object>{
    'recordId' => '0015000000XXXXX',           // Example Salesforce Record ID
    'recordType' => 'Opportunity',             // Type of record
    'action' => 'deploy',                      // What action to take
    'userName' => UserInfo.getName(),          // Current Salesforce user
    'message' => 'Opportunity closed - deploying configuration',
    'environment' => 'staging',                // Target environment
    'timestamp' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
};

Map<String, Object> requestBody = new Map<String, Object>{
    'event_type' => 'salesforce_event',        // Must match workflow types
    'client_payload' => clientPayload          // Your custom data
};

// STEP 3: Make the API call
String owner = 'gforceinnovation';             // Your GitHub username/org
String repo = 'sf-develop-demo';               // Your repository name

String endpoint = 'callout:GitHub_API/repos/' + owner + '/' + repo + '/dispatches';

HttpRequest req = new HttpRequest();
req.setEndpoint(endpoint);
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + installationToken);
req.setHeader('Accept', 'application/vnd.github+json');
req.setHeader('X-GitHub-Api-Version', '2022-11-28');
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(requestBody));
req.setTimeout(60000);

System.debug('📤 Sending request to: ' + endpoint);
System.debug('📦 Payload: ' + JSON.serializePretty(requestBody));

Http http = new Http();
HttpResponse res = http.send(req);

// STEP 4: Check response
System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
System.debug('📨 Response Status: ' + res.getStatusCode());

if (res.getStatusCode() == 204) {
    System.debug('✅ SUCCESS! Repository dispatch event triggered!');
    System.debug('🎯 Check GitHub Actions: https://github.com/' + owner + '/' + repo + '/actions');
} else {
    System.debug('❌ FAILED!');
    System.debug('Response: ' + res.getBody());
}
System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

