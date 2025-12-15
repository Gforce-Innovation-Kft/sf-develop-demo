# GitHub Actions Deployment Demo

A complete working example demonstrating how to trigger GitHub Actions workflows from Salesforce using repository dispatch events.

## 📋 What's Included

### 1. GitHub Actions Workflow

**File:** `.github/workflows/salesforce-deployment-demo.yml`

A production-ready workflow that:

- ✅ Accepts dispatch events from Salesforce
- ✅ Deploys to different environments (sandbox, staging, production)
- ✅ Runs Apex tests (configurable)
- ✅ Validates metadata before deployment
- ✅ Sends deployment status notifications
- ✅ Includes comprehensive logging

### 2. Lightning Web Component

**Component:** `deploymentDemo`

A user-friendly interface that:

- ✅ Allows environment selection
- ✅ Toggles Apex test execution
- ✅ Passes Salesforce record context
- ✅ Lists available workflows
- ✅ Shows real-time debug information
- ✅ Provides configuration overview

## 🚀 Quick Start

### Step 1: Deploy the Workflow to GitHub

```bash
# Navigate to your repository
cd /path/to/sf-develop-demo

# Create workflows directory if it doesn't exist
mkdir -p .github/workflows

# The workflow file is already created at:
# .github/workflows/salesforce-deployment-demo.yml

# Commit and push
git add .github/workflows/salesforce-deployment-demo.yml
git commit -m "Add Salesforce deployment demo workflow"
git push origin main
```

### Step 2: Configure GitHub Secrets

Add a Salesforce authentication URL to your GitHub repository:

```bash
# Generate SFDX Auth URL from your Salesforce org
sf org display --target-org your-sandbox-alias --verbose

# Copy the "Sfdx Auth Url" value

# Add to GitHub:
# Repository → Settings → Secrets and variables → Actions → New repository secret
# Name: SFDX_AUTH_URL_SANDBOX
# Value: force://[your-auth-url]
```

### Step 3: Deploy the LWC to Salesforce

```bash
# Deploy the component
sf project deploy start -d github-action-service/main/default/lwc/deploymentDemo

# Verify deployment
sf project deploy report
```

### Step 4: Add Component to Lightning Page

1. Navigate to Lightning App Builder:

   ```
   Setup → Lightning App Builder → New / Edit Page
   ```

2. Drag **"Deployment Demo"** component onto the page

3. Configure properties (optional):
   - GitHub Owner: `your-github-username`
   - GitHub Repository: `your-repo-name`

4. Save and activate the page

## 🎯 Using the Demo

### Trigger a Deployment

1. **Select Environment:**
   - 🏖️ Sandbox (for development)
   - 🎭 Staging (for testing)
   - 🚀 Production (for live deployment)

2. **Configure Options:**
   - ✅ Run Apex Tests (recommended)
   - Record ID (optional - for tracking)

3. **Click "🚀 Deploy Now"**

4. **Check GitHub Actions:**
   ```
   GitHub Repository → Actions tab
   ```

### Test Connection

Click **"📋 List Workflows"** to:

- Verify GitHub App authentication works
- See all available workflows in the repository
- Test the integration without triggering deployment

## 📊 Workflow Inputs Explained

| Input          | Type    | Description                           | Example                            |
| -------------- | ------- | ------------------------------------- | ---------------------------------- |
| `environment`  | choice  | Target Salesforce org                 | `sandbox`, `staging`, `production` |
| `deploy_tests` | boolean | Run Apex tests during deployment      | `true`, `false`                    |
| `triggered_by` | string  | Name of user who triggered deployment | `"John Doe"`                       |
| `record_id`    | string  | Salesforce record ID for context      | `"0015000000XXXXX"`                |

## 🔧 Customization Guide

### Update Repository Details

**In LWC (`deploymentDemo.js`):**

```javascript
// Configuration - Update these with your GitHub details
owner = "your-github-username";
repo = "your-repo-name";
workflowFileName = "salesforce-deployment-demo.yml";
branch = "main";
```

### Add More Environments

**In LWC (`deploymentDemo.js`):**

```javascript
get environmentOptions() {
    return [
        { label: '🏖️ Sandbox', value: 'sandbox' },
        { label: '🎭 Staging', value: 'staging' },
        { label: '🚀 Production', value: 'production' },
        { label: '🧪 QA', value: 'qa' },  // Add this
        { label: '🔧 Dev', value: 'dev' }  // Add this
    ];
}
```

**In Workflow (`.github/workflows/salesforce-deployment-demo.yml`):**

```yaml
environment:
  description: "Target environment"
  required: true
  type: choice
  options:
    - sandbox
    - staging
    - production
    - qa # Add this
    - dev # Add this
```

### Add Custom Workflow Inputs

**In Workflow:**

```yaml
on:
  workflow_dispatch:
    inputs:
      # ...existing inputs...
      notification_email:
        description: "Email for deployment notifications"
        required: false
        type: string
```

**In LWC:**

```javascript
// Add new property
@track notificationEmail = '';

// Add input handler
handleEmailChange(event) {
    this.notificationEmail = event.target.value;
}

// Update inputs in handleDeploy()
const inputs = {
    environment: this.selectedEnvironment,
    deploy_tests: this.deployTests,
    triggered_by: currentUser,
    notification_email: this.notificationEmail  // Add this
};
```

## 🎬 Demo Scenarios

### Scenario 1: Quick Sandbox Deployment

```
1. Select "Sandbox" environment
2. Keep "Run Apex Tests" checked
3. Click "Deploy Now"
4. Monitor in GitHub Actions
```

### Scenario 2: Production Deployment with Tracking

```
1. Select "Production" environment
2. Check "Run Apex Tests"
3. Enter opportunity/case Record ID
4. Click "Deploy Now"
5. Use Record ID to track deployment in Salesforce
```

### Scenario 3: Test Connection

```
1. Click "List Workflows"
2. Verify all workflows appear
3. Confirm "salesforce-deployment-demo.yml" is listed
```

## 🔍 Troubleshooting

### Issue: Workflow not appearing in list

**Check:**

1. Workflow file is in `.github/workflows/` directory
2. File has `.yml` or `.yaml` extension
3. File is committed and pushed to GitHub
4. GitHub App has `actions: read` permission

**Solution:**

```bash
# Verify file exists
ls -la .github/workflows/

# Check git status
git status

# Commit if needed
git add .github/workflows/salesforce-deployment-demo.yml
git commit -m "Add workflow"
git push
```

### Issue: "Failed to trigger workflow"

**Check:**

1. GitHub App has `actions: write` permission
2. Custom Metadata has correct App ID and Installation ID
3. Private key is valid and properly formatted
4. Repository name and owner are correct

**Debug:**

```javascript
// Add console logging in deploymentDemo.js
console.log("Request:", JSON.stringify(request, null, 2));
```

### Issue: Workflow starts but fails

**Check GitHub Actions logs:**

```
Repository → Actions → Select workflow run → View logs
```

**Common causes:**

- Missing `SFDX_AUTH_URL_SANDBOX` secret
- Invalid Salesforce credentials
- Metadata validation errors
- Test failures

## 📸 Screenshots

### LWC Component View

```
┌──────────────────────────────────────────────────┐
│ 🚀 Salesforce Deployment Demo                   │
├──────────────────────────────────────────────────┤
│ ℹ️ Trigger GitHub Actions workflows directly     │
│   from Salesforce using repository dispatch      │
│                                                  │
│ Target Environment *                             │
│ [🏖️ Sandbox ▼]                                  │
│                                                  │
│ ☑️ Run Apex Tests                                │
│                                                  │
│ Record ID (Optional)                             │
│ [________________]                               │
│                                                  │
│ [🚀 Deploy Now] [📋 List Workflows]             │
│                                                  │
│ 🔧 Quick Configuration                           │
│ Repository: gforceinnovation/sf-develop-demo    │
│ Workflow: salesforce-deployment-demo.yml        │
│ Branch: main                                     │
└──────────────────────────────────────────────────┘
```

### GitHub Actions Running

```
✅ Salesforce Deployment Demo #123
   Started by: Salesforce User

   ✅ Checkout code
   ✅ Display deployment info
   ✅ Setup Node.js
   ✅ Install Salesforce CLI
   ✅ Authenticate to Salesforce
   ⏳ Run Apex tests (in progress...)
```

## 🎓 Learning Points

This demo teaches:

1. **Workflow Dispatch Events**
   - How to accept inputs from external systems
   - Dynamic workflow execution

2. **LWC Development**
   - Apex integration
   - User input handling
   - Error management
   - Toast notifications

3. **GitHub Actions**
   - Multi-step workflows
   - Environment-specific logic
   - Secrets management
   - Status reporting

4. **Salesforce-GitHub Integration**
   - JWT authentication
   - Repository dispatch
   - Webhook callbacks
   - Security best practices

## 🔗 Related Documentation

- [Main Integration Overview](./README.md)
- [Setup Guide](./SETUP.md)
- [Security Best Practices](./SECURITY.md)
- [Quick Reference](./QUICKREF.md)

## 💡 Next Steps

### Enhance the Demo

1. **Add Deployment History**
   - Store deployment records in Salesforce
   - Track success/failure rates
   - Generate reports

2. **Webhook Notifications**
   - Receive deployment status in Salesforce
   - Update records when workflow completes
   - Send email notifications

3. **Multi-Repository Support**
   - Configure multiple repositories
   - Dynamic repository selection
   - Cross-repository deployments

4. **Approval Process**
   - Require approval before production
   - Implement approval workflows
   - Audit trail

### Production Readiness

1. **Error Handling**
   - Implement retry logic
   - Better error messages
   - Rollback capabilities

2. **Monitoring**
   - Dashboard for deployment status
   - Metrics and analytics
   - Alerting

3. **Documentation**
   - User guides
   - Runbooks
   - Training materials

## 🤝 Contributing

Feel free to customize this demo for your specific use case. Share your enhancements with the community!

---

**[← Back to Main Documentation](./README.md)**
