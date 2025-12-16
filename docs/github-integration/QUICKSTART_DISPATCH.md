# 🚀 Quick Start: Trigger GitHub Actions from Salesforce

**Goal:** Trigger a GitHub Action workflow from Salesforce in under 5 minutes!

## ⚠️ Prerequisites

**Check Your GitHub App Permissions First!**

Your GitHub App must have:

- ✅ **Contents: Read and write** (Required!)
- ✅ Actions: Read and write
- ✅ Metadata: Read-only

**Don't have these permissions?** [Fix it here](./FIX_403_DISPATCH.md) (takes 2 minutes)

## What You'll Do

1. Push a simple workflow to GitHub
2. Copy/paste Apex code
3. Execute and see it run!

## Step 1: Push Workflow (1 minute)

```bash
cd /Users/gaborbalint.demeter/gforce/sf-develop-demo
git add .github/workflows/salesforce-notification.yml
git commit -m "Add repository dispatch workflow"
git push
```

✅ Done! Workflow is now live on GitHub.

## Step 2: Execute Anonymous Apex (1 minute)

### Open Developer Console

1. In Salesforce, click the gear icon (⚙️) → **Developer Console**
2. Go to **Debug** → **Open Execute Anonymous Window**
3. Copy and paste this code:

```apex
// Get your JWT token
String token = GitHubAppAuthService.getInstallationToken();

// Create the payload
Map<String, Object> payload = new Map<String, Object>{
    'event_type' => 'salesforce_event',
    'client_payload' => new Map<String, Object>{
        'message' => 'Hello from Salesforce!',
        'recordId' => '0015000000ABC123',
        'action' => 'test',
        'userName' => UserInfo.getName()
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
    System.debug('❌ Error: ' + res.getStatusCode());
    System.debug('Response: ' + res.getBody());
}
```

4. Click **Execute**
5. Check the logs for `✅ SUCCESS!`

## Step 3: View Results (30 seconds)

1. Go to GitHub: `https://github.com/gforceinnovation/sf-develop-demo/actions`
2. You'll see your workflow running!
3. Click on it to see the output

**Expected Output:**

```
🎉 Repository Dispatch Event Received!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Event Type: salesforce_event
Triggered from: Salesforce
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Salesforce Payload:
  Record ID: 0015000000ABC123
  Record Type:
  Action: test
  User: Your Name
  Message: Hello from Salesforce!

✅ Event processed successfully!
```

## 🎉 Success!

You just triggered a GitHub Action from Salesforce using JWT authentication!

## What Just Happened?

1. **Apex got a JWT token** from your GitHub App
2. **Sent a repository_dispatch event** to GitHub API
3. **GitHub Actions workflow** received the event
4. **Workflow executed** and displayed your data

## Next Steps

### Customize the Payload

Change the `client_payload` to send different data:

```apex
'client_payload' => new Map<String, Object>{
    'recordId' => '0065000000XXXXX',     // Real record ID
    'recordType' => 'Account',           // Type
    'action' => 'deploy',                // Custom action
    'environment' => 'staging',          // Target env
    'customField' => 'Custom value'      // Any data!
}
```

### Create Your Own Workflow

Create `.github/workflows/my-workflow.yml`:

```yaml
name: My Custom Workflow

on:
  repository_dispatch:
    types: [my_event_type] # Change this

jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      - name: Do Something
        run: |
          echo "Record ID: ${{ github.event.client_payload.recordId }}"
          # Your custom logic here
```

Then trigger it:

```apex
'event_type' => 'my_event_type',  // Must match workflow
```

## 📚 Full Documentation

For more examples and details:

- **[Repository Dispatch Guide](./REPOSITORY_DISPATCH.md)** - Complete examples
- **[Setup Guide](./SETUP.md)** - Initial configuration
- **[Security](./SECURITY.md)** - Security best practices

## 🆘 Troubleshooting

### Error: 401 Unauthorized

```apex
// Check your token works
String token = GitHubAppAuthService.getInstallationToken();
System.debug('Token: ' + token.substring(0, 10) + '...');
```

### Error: 404 Not Found

Check the endpoint matches your repo:

```apex
'callout:GitHub_API/repos/YOUR-USERNAME/YOUR-REPO/dispatches'
```

### No Workflow Appears

1. Ensure workflow file is in `.github/workflows/`
2. Ensure it's pushed to the default branch (main)
3. Check `event_type` matches workflow `types`

---

**You're all set! 🎉 Start triggering workflows from Salesforce!**
