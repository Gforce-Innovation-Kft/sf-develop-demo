# Quick Reference - GitHub Actions Integration

Essential commands and snippets for working with the GitHub Actions integration.

## 🚀 Common Commands

### Salesforce CLI

```bash
# Deploy the integration
sf project deploy start -d github-action-service

# Assign permission set
sf org assign permset -n GitHub_Integration_Admin

# Run tests
sf apex run test --tests GitHubActionsServiceTest --code-coverage

# Tail logs
sf apex tail log --color

# View recent logs
sf apex get log --number 5
```

### Key Conversion

```bash
# Convert PEM to base64 (macOS/Linux)
cat github-app-private-key.pem | grep -v "BEGIN\|END" | tr -d '\n' > key_base64.txt

# Generate webhook secret
openssl rand -hex 32

# Verify base64 key is single line
wc -l key_base64.txt  # Should output: 1
```

## 📝 Code Snippets

### List Workflows

```apex
// Apex
GitHubActionsService.WorkflowListRequest request = new GitHubActionsService.WorkflowListRequest();
request.owner = 'gforceinnovation';
request.repo = 'sf-develop-demo';

GitHubActionsService.WorkflowListResponse response = GitHubActionsService.listWorkflows(request);
System.debug('Total workflows: ' + response.totalCount);
```

```javascript
// LWC
import listWorkflows from "@salesforce/apex/GitHubActionsService.listWorkflows";

listWorkflows({ owner: "myorg", repo: "myrepo" })
  .then((result) => {
    console.log("Workflows:", result.workflows);
  })
  .catch((error) => {
    console.error("Error:", error);
  });
```

### Trigger Workflow

```apex
// Apex
GitHubActionsService.WorkflowTriggerRequest request = new GitHubActionsService.WorkflowTriggerRequest();
request.owner = 'gforceinnovation';
request.repo = 'sf-develop-demo';
request.workflowId = 'deploy-staging.yml';
request.ref = 'main';
request.inputs = new Map<String, Object>{
    'environment' => 'staging',
    'triggered_by' => 'Salesforce'
};

GitHubActionsService.triggerWorkflow(request);
```

```javascript
// LWC
import triggerWorkflow from "@salesforce/apex/GitHubActionsService.triggerWorkflow";

triggerWorkflow({
  owner: "myorg",
  repo: "myrepo",
  workflowId: "deploy.yml",
  ref: "main",
  inputs: { triggered_by: "Salesforce" }
})
  .then(() => {
    console.log("Workflow triggered successfully");
  })
  .catch((error) => {
    console.error("Error:", error);
  });
```

### Test JWT Generation

```apex
// Execute Anonymous
String appId = '123456';
String privateKeyBase64 = 'MIIEvgIBADANBgkqhkiG9w0BA...'; // Your base64 key

try {
    String jwt = GitHubAppAuthService.generateJWT(appId, privateKeyBase64);
    System.debug('JWT generated successfully: ' + jwt.substring(0, 20) + '...');
} catch (Exception e) {
    System.debug('Error: ' + e.getMessage());
}
```

### Test Installation Token

```apex
// Execute Anonymous
try {
    String token = GitHubAppAuthService.getInstallationToken();
    System.debug('Token retrieved: ' + token.substring(0, 10) + '...');
} catch (Exception e) {
    System.debug('Error: ' + e.getMessage());
}
```

## 🔍 Debugging Tips

### Check Custom Metadata

```apex
// Execute Anonymous
GitHub_App_Settings__mdt settings = [
    SELECT App_Id__c, Installation_Id__c, Webhook_Secret__c
    FROM GitHub_App_Settings__mdt
    WHERE DeveloperName = 'salesforce_gforce_devhub'
    LIMIT 1
];

System.debug('App ID: ' + settings.App_Id__c);
System.debug('Installation ID: ' + settings.Installation_Id__c);
System.debug('Webhook Secret Length: ' + settings.Webhook_Secret__c?.length());
```

### Test Webhook Signature

```bash
# Generate test signature
PAYLOAD='{"action":"completed"}'
SECRET='your-webhook-secret'
SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.* //')
echo "sha256=$SIGNATURE"

# Test webhook endpoint
curl -X POST https://your-org.my.salesforce.com/services/apexrest/githubwebhook \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: workflow_run" \
  -H "X-Hub-Signature-256: sha256=$SIGNATURE" \
  -d "$PAYLOAD"
```

## 📊 SOQL Queries

### Find All Workflow Records (if using custom object)

```sql
SELECT Id, Name, Workflow_Name__c, Status__c, Conclusion__c, Run_Id__c
FROM GitHub_Workflow_Run__c
WHERE CreatedDate = TODAY
ORDER BY CreatedDate DESC
LIMIT 10
```

### Check Permission Set Assignments

```sql
SELECT Id, Assignee.Name, PermissionSet.Name
FROM PermissionSetAssignment
WHERE PermissionSet.Name = 'GitHub_Integration_Admin'
```

### View Setup Audit Trail

```sql
SELECT Id, Action, Section, CreatedBy.Name, CreatedDate
FROM SetupAuditTrail
WHERE Section LIKE '%GitHub%'
ORDER BY CreatedDate DESC
LIMIT 20
```

## 🔧 Troubleshooting Commands

### Common Questions

**Q: Why not use Salesforce External Credentials with certificates?**

**A:** GitHub App private keys are incompatible with Salesforce's certificate requirements:

| GitHub Provides         | Salesforce Requires                  |
| ----------------------- | ------------------------------------ |
| PKCS#1/PKCS#8 format    | X.509 certificate format             |
| Standalone RSA key      | Complete certificate chain           |
| No certificate metadata | Issuer, subject, validity period     |
| Self-signed by GitHub   | CA-signed or proper self-signed cert |

**Attempted conversion breaks GitHub's signature verification**, so we use Protected Custom Metadata to store the base64-encoded key directly. This provides equivalent security without format conversion issues.

### Clear Org Cache

```apex
// Execute Anonymous
Cache.Org.remove('github_installation_token');
System.debug('Cache cleared');
```

### Test API Connectivity

```bash
# Test GitHub API directly
curl -H "Authorization: Bearer YOUR_INSTALLATION_TOKEN" \
  https://api.github.com/repos/owner/repo/actions/workflows
```

### Check Rate Limits

```apex
// Execute Anonymous
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:GitHub_API/rate_limit');
req.setMethod('GET');
req.setHeader('Authorization', 'Bearer ' + GitHubAppAuthService.getInstallationToken());

Http http = new Http();
HttpResponse res = http.send(req);
System.debug('Rate Limit Info: ' + res.getBody());
```

## 📋 Environment Variables

### Custom Metadata Record Structure

```
Label: Salesforce GForce DevHub
Developer Name: salesforce_gforce_devhub
App ID: 123456
Installation ID: 12345678
Private Key Base64: MIIEvgIBADANBgkqhkiG9w0BA...
Webhook Secret: a1b2c3d4e5f6...
```

### Named Credential

```
Name: GitHub_API
URL: https://api.github.com
Identity Type: Anonymous
```

## 🔗 Useful URLs

### GitHub App Settings

```
https://github.com/settings/apps/YOUR_APP_NAME
https://github.com/organizations/YOUR_ORG/settings/apps/YOUR_APP_NAME
```

### Salesforce Setup Pages

```
Setup → Custom Metadata Types → GitHub App Settings
Setup → Named Credentials → GitHub_API
Setup → Permission Sets → GitHub Integration Admin
Setup → Debug Logs
Setup → Setup Audit Trail
```

### REST Endpoints

```
Webhook: /services/apexrest/githubwebhook
```

## 📚 Key Values to Note

### GitHub API Limits

- **Rate Limit:** 5,000 requests/hour per installation
- **JWT Expiry:** 10 minutes maximum
- **Installation Token Expiry:** 1 hour
- **Webhook Timeout:** 10 seconds

### Salesforce Limits

- **Callout Timeout:** 120 seconds (default)
- **Callout Limit:** 100 per transaction
- **Heap Size:** 6MB (synchronous), 12MB (asynchronous)
- **CPU Time:** 10,000ms (synchronous), 60,000ms (asynchronous)

## 🎯 Quick Checks

### ✅ Integration Health Check

```apex
// Execute Anonymous - Full health check
public class HealthCheck {
    public static void run() {
        System.debug('=== GitHub Integration Health Check ===');

        // 1. Check Custom Metadata
        try {
            GitHub_App_Settings__mdt settings = [
                SELECT App_Id__c, Installation_Id__c
                FROM GitHub_App_Settings__mdt
                LIMIT 1
            ];
            System.debug('✅ Custom Metadata: OK');
        } catch (Exception e) {
            System.debug('❌ Custom Metadata: FAILED - ' + e.getMessage());
            return;
        }

        // 2. Check JWT Generation
        try {
            String jwt = GitHubAppAuthService.generateJWT();
            System.debug('✅ JWT Generation: OK');
        } catch (Exception e) {
            System.debug('❌ JWT Generation: FAILED - ' + e.getMessage());
            return;
        }

        // 3. Check Installation Token
        try {
            String token = GitHubAppAuthService.getInstallationToken();
            System.debug('✅ Installation Token: OK');
        } catch (Exception e) {
            System.debug('❌ Installation Token: FAILED - ' + e.getMessage());
            return;
        }

        // 4. Check API Connectivity
        try {
            GitHubActionsService.WorkflowListRequest req =
                new GitHubActionsService.WorkflowListRequest();
            req.owner = 'gforceinnovation';
            req.repo = 'sf-develop-demo';
            GitHubActionsService.listWorkflows(req);
            System.debug('✅ API Connectivity: OK');
        } catch (Exception e) {
            System.debug('❌ API Connectivity: FAILED - ' + e.getMessage());
            return;
        }

        System.debug('=== All Checks Passed! ===');
    }
}

HealthCheck.run();
```

## 🎓 Learning Resources

- [Architecture Overview](./README.md)
- [Setup Guide](./SETUP.md)
- [Security Best Practices](./SECURITY.md)
- [GitHub Apps Docs](https://docs.github.com/en/apps)
- [Salesforce Apex Docs](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)

---

**[← Back to Overview](./README.md)**
