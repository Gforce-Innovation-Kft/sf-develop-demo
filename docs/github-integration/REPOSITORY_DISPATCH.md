# Repository Dispatch Examples

Easy examples for triggering GitHub Actions from Salesforce using `repository_dispatch` events.

## ⚠️ Important: Required Permissions

**Before using repository_dispatch, ensure your GitHub App has:**

| Permission   | Required Level        |
| ------------ | --------------------- |
| **Contents** | ✅ **Read and write** |
| Actions      | ✅ Read and write     |
| Metadata     | ✅ Read-only          |

**Why Contents: write?** The `repository_dispatch` API endpoint requires write access to repository contents. Without it, you'll get a `403 Forbidden` error.

**Don't have Contents: write?** See [Fix: 403 Error Guide](./FIX_403_DISPATCH.md) for step-by-step instructions to update permissions.

## 🎯 What is repository_dispatch?

`repository_dispatch` allows you to trigger GitHub Actions workflows from external events (like Salesforce). Unlike `workflow_dispatch` (which requires inputs), `repository_dispatch` is more flexible and lets you send any data through `client_payload`.

## 📁 Files Created

### GitHub Actions Workflows

1. **`salesforce-notification.yml`** - General purpose Salesforce event handler
2. **`test-result-handler.yml`** - Handles test results from Salesforce

### Anonymous Apex Scripts

1. **`simple-trigger.apex`** - Minimal example (10 lines!)
2. **`trigger-github-dispatch.apex`** - Full documented example

## 🚀 Quick Start (3 Steps!)

### Step 1: Push Workflow to GitHub

```bash
cd /Users/gaborbalint.demeter/gforce/sf-develop-demo
git add .github/workflows/salesforce-notification.yml
git commit -m "Add repository dispatch workflow"
git push
```

### Step 2: Copy Anonymous Apex

Open **Developer Console** → **Debug** → **Open Execute Anonymous Window**

Copy and paste this:

```apex
// Get token
String token = GitHubAppAuthService.getInstallationToken();

// Create payload
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

if (res.getStatusCode() == 204) {
    System.debug('✅ SUCCESS!');
} else {
    System.debug('❌ Error: ' + res.getBody());
}
```

### Step 3: Execute and Check

1. Click **Execute**
2. Check logs for `✅ SUCCESS!`
3. Go to GitHub → Actions tab
4. See your workflow running!

## 📊 Example 1: Salesforce Notification

**Workflow:** `salesforce-notification.yml`

**What it does:**

- Receives any Salesforce event
- Displays payload data
- Runs conditional steps based on action type

**Trigger with Apex:**

```apex
String token = GitHubAppAuthService.getInstallationToken();

Map<String, Object> payload = new Map<String, Object>{
    'event_type' => 'salesforce_event',
    'client_payload' => new Map<String, Object>{
        'recordId' => '0065000000XXXXX',
        'recordType' => 'Account',
        'action' => 'deploy',
        'userName' => UserInfo.getName(),
        'message' => 'Account updated - deploy changes',
        'environment' => 'staging'
    }
};

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:GitHub_API/repos/gforceinnovation/sf-develop-demo/dispatches');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + token);
req.setHeader('Accept', 'application/vnd.github+json');
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(payload));

new Http().send(req);
```

**GitHub Workflow Output:**

```
🎉 Repository Dispatch Event Received!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Event Type: salesforce_event
Triggered from: Salesforce
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Salesforce Payload:
  Record ID: 0065000000XXXXX
  Record Type: Account
  Action: deploy
  User: John Doe
  Message: Account updated - deploy changes

🚀 Deployment action detected!
Would deploy to: staging

✅ Event processed successfully!
```

## 📊 Example 2: Test Results

**Workflow:** `test-result-handler.yml`

**What it does:**

- Receives test results from Salesforce
- Shows different output for pass/fail
- Can trigger notifications on failure

**Trigger with Apex:**

```apex
// Simulate test failure
String token = GitHubAppAuthService.getInstallationToken();

Map<String, Object> payload = new Map<String, Object>{
    'event_type' => 'test_result',
    'client_payload' => new Map<String, Object>{
        'passed' => false,
        'message' => 'Error: timeout',
        'testSuite' => 'AccountTriggerTest',
        'errorDetails' => 'System.LimitException: Apex CPU time limit exceeded',
        'coverage' => 72
    }
};

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:GitHub_API/repos/gforceinnovation/sf-develop-demo/dispatches');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + token);
req.setHeader('Accept', 'application/vnd.github+json');
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(payload));

new Http().send(req);
```

**GitHub Workflow Output:**

```
Test Status: false
Message: Error: timeout
Test Suite: AccountTriggerTest

❌ Tests Failed!
Message: Error: timeout
Details: System.LimitException: Apex CPU time limit exceeded
Notifying team...
```

## 🎨 Customization

### Add More Event Types

**In Workflow:**

```yaml
on:
  repository_dispatch:
    types:
      - salesforce_event
      - test_result
      - deployment_complete # Add this
      - opportunity_closed # Add this
```

**In Apex:**

```apex
// Change event_type to match
'event_type' => 'deployment_complete'
```

### Add More Payload Data

**In Apex:**

```apex
'client_payload' => new Map<String, Object>{
    'recordId' => '0015000000XXXXX',
    'customField1' => 'value1',
    'customField2' => 123,
    'customField3' => true,
    'nestedObject' => new Map<String, Object>{
        'key1' => 'value1'
    }
}
```

**Access in Workflow:**

```yaml
- name: Use Custom Fields
  env:
    FIELD1: ${{ github.event.client_payload.customField1 }}
    FIELD2: ${{ github.event.client_payload.customField2 }}
    NESTED: ${{ github.event.client_payload.nestedObject.key1 }}
  run: echo "$FIELD1 - $FIELD2 - $NESTED"
```

## 🔍 Debugging

### Check Apex Logs

```apex
System.debug('Token: ' + token.substring(0, 10) + '...');
System.debug('Payload: ' + JSON.serializePretty(payload));
System.debug('Response: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody());
```

### Check GitHub

1. Go to: `https://github.com/gforceinnovation/sf-develop-demo/actions`
2. Look for your workflow run
3. Click to see detailed logs

### Common Issues

| Error               | Solution                                                            |
| ------------------- | ------------------------------------------------------------------- |
| `401 Unauthorized`  | Check token is valid: `GitHubAppAuthService.getInstallationToken()` |
| `404 Not Found`     | Verify repo owner/name in endpoint                                  |
| `422 Unprocessable` | Check `event_type` matches workflow `types`                         |
| `No workflow runs`  | Ensure workflow is pushed to default branch (main)                  |

## 📚 API Reference

### GitHub API Endpoint

```
POST /repos/{owner}/{repo}/dispatches
```

### Request Body

```json
{
  "event_type": "string", // Required: matches workflow types
  "client_payload": {
    // Optional: any JSON data
    "key": "value"
  }
}
```

### Response

- **204 No Content** - Success (no response body)
- **401** - Authentication failed
- **404** - Repository not found
- **422** - Validation failed

## 🎓 Differences: workflow_dispatch vs repository_dispatch

| Feature              | workflow_dispatch                 | repository_dispatch          |
| -------------------- | --------------------------------- | ---------------------------- |
| **Defined inputs**   | ✅ Yes, in workflow file          | ❌ No, free-form payload     |
| **UI trigger**       | ✅ Yes, from GitHub UI            | ❌ API only                  |
| **Input validation** | ✅ Type checking                  | ❌ No validation             |
| **Flexibility**      | ⚠️ Limited to defined inputs      | ✅ Send any JSON data        |
| **Best for**         | Manual triggers with known inputs | External system integrations |

**Use `workflow_dispatch` when:**

- You want GitHub UI buttons
- You need input validation
- Inputs are known and fixed

**Use `repository_dispatch` when:**

- Triggering from external systems (like Salesforce)
- Payload structure varies
- Maximum flexibility needed

## 💡 Real-World Use Cases

### 1. Deployment Trigger

When a specific record is updated in Salesforce, trigger deployment to staging:

```apex
// In Apex Trigger or Process Builder
if (record.Status__c == 'Approved') {
    // Trigger deployment
    dispatch('salesforce_event', new Map<String, Object>{
        'action' => 'deploy',
        'environment' => 'staging',
        'recordId' => record.Id
    });
}
```

### 2. Test Result Notification

After running Apex tests, send results to GitHub:

```apex
// After test run
dispatch('test_result', new Map<String, Object>{
    'passed' => testsPassed,
    'coverage' => coveragePercent,
    'message' => testMessage
});
```

### 3. Data Sync

Sync Salesforce data changes to external system via GitHub Actions:

```apex
// On Account update
dispatch('data_sync', new Map<String, Object>{
    'recordType' => 'Account',
    'recordId' => acc.Id,
    'fields' => new Map<String, Object>{
        'Name' => acc.Name,
        'Industry' => acc.Industry
    }
});
```

## 📖 Further Reading

- [GitHub: repository_dispatch event](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#repository_dispatch)
- [GitHub REST API: Create a repository dispatch event](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event)
- [Salesforce: HTTP Callouts](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_restful_http_httprequest.htm)

## 🎉 You're Ready!

You now have:

- ✅ 2 working GitHub Actions workflows
- ✅ 2 Anonymous Apex scripts (simple & detailed)
- ✅ Complete documentation
- ✅ Real-world examples

Just push the workflows and run the Apex! 🚀

---

**[← Back to Main Documentation](./README.md)**
