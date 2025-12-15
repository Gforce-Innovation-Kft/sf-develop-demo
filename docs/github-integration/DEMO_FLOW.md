# Demo Flow Visualization

## Complete Integration Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SALESFORCE ORG                               │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Lightning Page with "Deployment Demo" Component           │    │
│  │                                                             │    │
│  │  ┌───────────────────────────────────────────────────┐     │    │
│  │  │  🚀 Salesforce Deployment Demo                    │     │    │
│  │  ├───────────────────────────────────────────────────┤     │    │
│  │  │  Target Environment: [Sandbox ▼]                  │     │    │
│  │  │  ☑ Run Apex Tests                                 │     │    │
│  │  │  Record ID: [0015000000XXXXX]                     │     │    │
│  │  │                                                    │     │    │
│  │  │  [🚀 Deploy Now]  [📋 List Workflows]            │     │    │
│  │  └───────────────────────────────────────────────────┘     │    │
│  │                            │                                │    │
│  │                            │ User clicks "Deploy Now"       │    │
│  │                            ▼                                │    │
│  │  ┌───────────────────────────────────────────────────┐     │    │
│  │  │  deploymentDemo.js                                │     │    │
│  │  │  • Collects user inputs                           │     │    │
│  │  │  • Calls GitHubActionsService.triggerWorkflow()  │     │    │
│  │  └────────────────────────┬──────────────────────────┘     │    │
│  └───────────────────────────┼────────────────────────────────┘    │
│                              │                                      │
│                              ▼                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  GitHubActionsService.triggerWorkflow()                    │    │
│  │  • owner: "gforceinnovation"                              │    │
│  │  • repo: "sf-develop-demo"                                │    │
│  │  • workflowId: "salesforce-deployment-demo.yml"           │    │
│  │  • inputs: { environment, deploy_tests, triggered_by }    │    │
│  └────────────────────────────┬───────────────────────────────┘    │
│                               │                                     │
│                               ▼                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  GitHubAppAuthService.getInstallationToken()               │    │
│  │  1. Read GitHub_App_Settings__mdt                         │    │
│  │  2. Generate JWT token (10-min expiry)                    │    │
│  │  3. Exchange JWT for installation token (1-hour)          │    │
│  └────────────────────────────┬───────────────────────────────┘    │
└────────────────────────────────┼────────────────────────────────────┘
                                 │
                                 │ HTTPS POST
                                 │ Authorization: Bearer <token>
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         GITHUB API                                   │
│  https://api.github.com                                             │
│                                                                      │
│  POST /repos/gforceinnovation/sf-develop-demo/                     │
│       actions/workflows/salesforce-deployment-demo.yml/dispatches   │
│                                                                      │
│  Body: {                                                            │
│    "ref": "main",                                                   │
│    "inputs": {                                                      │
│      "environment": "sandbox",                                      │
│      "deploy_tests": true,                                          │
│      "triggered_by": "Salesforce User",                            │
│      "record_id": "0015000000XXXXX"                                │
│    }                                                                │
│  }                                                                  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ 204 No Content (Success)
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    GITHUB ACTIONS RUNNER                             │
│  .github/workflows/salesforce-deployment-demo.yml                   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  Job: salesforce-deployment                              │      │
│  │  ✅ Checkout code                                        │      │
│  │  ✅ Display deployment info                              │      │
│  │  ✅ Setup Node.js                                        │      │
│  │  ✅ Install Salesforce CLI                               │      │
│  │  ✅ Authenticate to Salesforce (using SFDX_AUTH_URL)     │      │
│  │  ✅ Validate metadata                                    │      │
│  │  ✅ Run Apex tests (if deploy_tests = true)             │      │
│  │  ✅ Deploy to Salesforce                                 │      │
│  │  ✅ Post-deployment verification                         │      │
│  │  ✅ Deployment summary                                   │      │
│  └──────────────────────────────────────────────────────────┘      │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  Job: notify-salesforce (Future Enhancement)             │      │
│  │  • Prepare notification payload                          │      │
│  │  • Send webhook back to Salesforce                       │      │
│  │  • Include deployment status                             │      │
│  └──────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. LWC Component (`deploymentDemo`)

```javascript
Files:
- deploymentDemo.html      → User interface
- deploymentDemo.js        → Business logic
- deploymentDemo.css       → Styling
- deploymentDemo.js-meta.xml → Metadata config

Key Features:
• Environment selection
• Test execution toggle
• Record ID tracking
• Debug information display
```

### 2. Apex Service Layer

```apex
Classes:
- GitHubActionsService     → Workflow triggering
- GitHubAppAuthService     → JWT & token management
- GitHubWebhookService     → Webhook processing

Security:
• Protected Custom Metadata
• JWT authentication
• Short-lived tokens
```

### 3. GitHub Actions Workflow

```yaml
File: .github/workflows/salesforce-deployment-demo.yml

Inputs:
  - environment      → Target org
  - deploy_tests     → Run tests?
  - triggered_by     → Who triggered
  - record_id        → Tracking ID

Jobs:
  - salesforce-deployment  → Main deployment
  - notify-salesforce      → Send status back
```

## Data Flow Example

### User Action → GitHub Actions

```json
User selects in UI:
{
  "environment": "sandbox",
  "deployTests": true,
  "recordId": "0015000000XXXXX"
}

↓ Transformed by LWC

Sent to Apex:
{
  "owner": "gforceinnovation",
  "repo": "sf-develop-demo",
  "workflowId": "salesforce-deployment-demo.yml",
  "ref": "main",
  "inputs": {
    "environment": "sandbox",
    "deploy_tests": true,
    "triggered_by": "John Doe",
    "record_id": "0015000000XXXXX"
  }
}

↓ Apex calls GitHub API

GitHub Actions receives:
workflow_dispatch event with inputs

↓ Workflow executes

Deployment completes:
Status logged in GitHub Actions
```

## Quick Start Checklist

```
□ Step 1: Deploy workflow to GitHub
  git add .github/workflows/salesforce-deployment-demo.yml
  git commit -m "Add deployment workflow"
  git push

□ Step 2: Configure GitHub secrets
  Repository → Settings → Secrets
  Add: SFDX_AUTH_URL_SANDBOX

□ Step 3: Deploy LWC to Salesforce
  sf project deploy start -d github-action-service/main/default/lwc/deploymentDemo

□ Step 4: Add component to Lightning page
  Setup → Lightning App Builder
  Drag "Deployment Demo" to page

□ Step 5: Test the integration
  • Click "List Workflows" to test connection
  • Select environment
  • Click "Deploy Now"
  • Check GitHub Actions tab

✅ Done!
```

## Customization Points

### Change Repository

```javascript
// In deploymentDemo.js
owner = "YOUR-GITHUB-ORG";
repo = "YOUR-REPO-NAME";
```

### Add Environments

```javascript
// In deploymentDemo.js
get environmentOptions() {
    return [
        { label: '🏖️ Sandbox', value: 'sandbox' },
        { label: '🎭 Staging', value: 'staging' },
        { label: '🚀 Production', value: 'production' },
        { label: '🧪 QA', value: 'qa' },  // Add this
    ];
}
```

```yaml
# In workflow file
environment:
  type: choice
  options:
    - sandbox
    - staging
    - production
    - qa # Add this
```

### Add Custom Inputs

```javascript
// In deploymentDemo.js - Add property
@track customField = '';

// In handleDeploy() - Add to inputs
const inputs = {
    environment: this.selectedEnvironment,
    deploy_tests: this.deployTests,
    custom_field: this.customField  // Add this
};
```

```yaml
# In workflow file
on:
  workflow_dispatch:
    inputs:
      custom_field:
        description: "Custom field description"
        required: false
        type: string
```

## Error Handling Flow

```
User clicks "Deploy Now"
         │
         ▼
    Input validation
         │
         ├─ Invalid? → Show error toast
         │              Stop
         │
         ▼
    Call Apex method
         │
         ├─ Network error? → Catch & show toast
         │                    Log to debug
         │
         ▼
    GitHub API call
         │
         ├─ 401 Auth error? → Check credentials
         ├─ 404 Not found? → Check workflow name
         ├─ 403 Forbidden? → Check permissions
         │
         ▼
    Success!
         │
         ▼
    Show success toast
    Update debug info
```

## Security Flow

```
┌──────────────────────────────────────────────┐
│ Security Layer 1: Permission Set             │
│ Only authorized users can access component   │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│ Security Layer 2: Protected Custom Metadata  │
│ Credentials not exposed through UI/API       │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│ Security Layer 3: JWT Generation             │
│ 10-minute expiry, RSA-SHA256 signature       │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│ Security Layer 4: Installation Token         │
│ 1-hour expiry, scoped permissions            │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│ Security Layer 5: HTTPS/TLS                  │
│ Encrypted communication                      │
└──────────────────────────────────────────────┘
```

---

**[← Back to Demo Documentation](./DEMO.md)**
