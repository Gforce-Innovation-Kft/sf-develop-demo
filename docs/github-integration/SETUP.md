# Setup Guide - GitHub Actions Integration

Complete step-by-step instructions for configuring the GitHub Actions integration in Salesforce.

## 📋 Prerequisites

Before you begin, ensure you have:

- ✅ GitHub organization or repository with admin access
- ✅ Salesforce org (sandbox or production)
- ✅ Salesforce CLI installed (`sf` command)
- ✅ OpenSSL installed (for key conversion)
- ✅ Git installed

## 🚀 Step 1: Create GitHub App

### 1.1 Navigate to GitHub App Settings

**For an organization:**

```
GitHub → Your Organization → Settings → Developer settings → GitHub Apps → New GitHub App
```

**For a personal account:**

```
GitHub → Settings → Developer settings → GitHub Apps → New GitHub App
```

### 1.2 Configure GitHub App

Fill in the following fields:

| Field               | Value                                                                  |
| ------------------- | ---------------------------------------------------------------------- |
| **GitHub App name** | `Salesforce Integration - [Your Org Name]`                             |
| **Homepage URL**    | Your Salesforce org URL (e.g., `https://mycompany.my.salesforce.com`)  |
| **Webhook URL**     | `https://[your-org].my.salesforce.com/services/apexrest/githubwebhook` |
| **Webhook secret**  | Generate a strong random string (save this!)                           |

**Example webhook secret generation:**

```bash
openssl rand -hex 32
```

### 1.3 Set Permissions

Under **Repository permissions**, set:

| Permission   | Access                        |
| ------------ | ----------------------------- |
| **Actions**  | Read and write                |
| **Contents** | Read-only                     |
| **Metadata** | Read-only (automatically set) |

### 1.4 Subscribe to Events

Under **Subscribe to events**, select:

- ✅ Workflow job
- ✅ Workflow run

### 1.5 Where can this GitHub App be installed?

Choose one:

- ☑️ **Only on this account** (recommended for testing)
- ☐ Any account

### 1.6 Create the App

Click **Create GitHub App** button.

### 1.7 Note the App ID

After creation, you'll see your **App ID** on the app settings page. **Save this number!**

Example: `123456`

## 🔑 Step 2: Generate Private Key

### 2.1 Generate Key in GitHub

On your GitHub App settings page:

1. Scroll to **Private keys** section
2. Click **Generate a private key**
3. A `.pem` file will download automatically
4. **Save this file securely!**

### 2.2 Convert Private Key to Base64

The private key needs to be converted to base64 format without headers/footers for storage in Salesforce.

**macOS/Linux:**

```bash
cat your-github-app.pem | grep -v "BEGIN\|END" | tr -d '\n' > private_key_base64.txt
```

**Windows (PowerShell):**

```powershell
Get-Content your-github-app.pem | Where-Object { $_ -notmatch "BEGIN|END" } | Out-String | ForEach-Object { $_.Replace("`r`n","").Replace("`n","") } | Set-Content private_key_base64.txt
```

The resulting `private_key_base64.txt` should be a single line of base64 text without any line breaks.

### 2.3 Verify the Key

```bash
# Check it's a single line
wc -l private_key_base64.txt
# Output should be: 1 private_key_base64.txt

# Check length (should be ~1600-3200 characters)
wc -c private_key_base64.txt
```

## 📦 Step 3: Install GitHub App on Repository

### 3.1 Install App

1. Go to your GitHub App settings page
2. Click **Install App** in the left sidebar
3. Select your organization
4. Choose repositories:
   - ☑️ **Only select repositories** → Select your target repo
   - ☐ All repositories
5. Click **Install**

### 3.2 Get Installation ID

After installation, look at the URL in your browser:

```
https://github.com/organizations/YOUR_ORG/settings/installations/12345678
                                                                   ^^^^^^^^
                                                                   This is your Installation ID
```

**Save this Installation ID!**

## ⚙️ Step 4: Deploy to Salesforce

### 4.1 Clone or Download the Project

```bash
git clone https://github.com/yourorg/sf-develop-demo.git
cd sf-develop-demo
```

### 4.2 Authenticate to Your Org

**For scratch org:**

```bash
sf org login web -a MyScratchOrg -d
```

**For sandbox:**

```bash
sf org login web -a MySandbox -r https://test.salesforce.com
```

**For production:**

```bash
sf org login web -a MyProd -r https://login.salesforce.com
```

### 4.3 Deploy Metadata

```bash
# Deploy all metadata
sf project deploy start

# Or deploy specific package
sf project deploy start -d github-action-service
```

### 4.4 Verify Deployment

```bash
# Check deployment status
sf project deploy report
```

## 🔐 Step 5: Configure Custom Metadata

### 5.1 Navigate to Custom Metadata Types

```
Setup → Custom Metadata Types → GitHub App Settings → Manage Records
```

### 5.2 Create New Record

Click **New** and fill in the following:

| Field                  | Value                               | Example                    |
| ---------------------- | ----------------------------------- | -------------------------- |
| **Label**              | `Salesforce GForce DevHub`          | `Salesforce GForce DevHub` |
| **Developer Name**     | `salesforce_gforce_devhub`          | `salesforce_gforce_devhub` |
| **App ID**             | Your GitHub App ID                  | `123456`                   |
| **Installation ID**    | Your Installation ID                | `12345678`                 |
| **Webhook Secret**     | The webhook secret you generated    | `a1b2c3d4...`              |
| **Private Key Base64** | Content of `private_key_base64.txt` | `MIIEvgIBADAN...`          |

### 5.3 Save Record

Click **Save**.

## 👥 Step 6: Assign Permission Set

### 6.1 Assign to Users

```bash
# Assign to current user
sf org assign permset -n GitHub_Integration_Admin

# Or via UI: Setup → Permission Sets → GitHub Integration Admin → Manage Assignments
```

### 6.2 Verify Permissions

Ensure the permission set includes:

- Custom Metadata Type: `GitHub_App_Settings__mdt` (Read)
- Apex Classes: `GitHubAppAuthService`, `GitHubActionsService`, `GitHubWebhookService`
- Custom Permissions: Any custom permissions created

## 🎨 Step 7: Add LWC Component to Page

### 7.1 Navigate to Lightning App Builder

```
Setup → Lightning App Builder → New
```

Or edit an existing page:

```
App Launcher → [Your App] → Home → Edit Page (gear icon)
```

### 7.2 Add Component

1. Drag **GitHub Action Trigger** component from the component list
2. Place it in your desired layout section
3. Click **Save**
4. Click **Activate** (if new page)

## ✅ Step 8: Test the Integration

### 8.1 Test Connection

1. Navigate to the page with the LWC component
2. Click **"Test Connection & List Workflows"** button
3. Verify you see:
   - ✅ Success message
   - ✅ List of workflows from your repository

### 8.2 Review Debug Logs

```bash
# Start log streaming
sf apex tail log --color
```

In another terminal:

```bash
# Trigger a test from the UI
# Watch the logs in real-time
```

### 8.3 Trigger a Workflow

1. Select a workflow from the dropdown
2. Enter a branch name (e.g., `main`)
3. Click **"Trigger Workflow"**
4. Verify:
   - ✅ Success toast in Salesforce
   - ✅ Workflow appears in GitHub Actions tab

## 🔧 Step 9: Configure Webhook Testing (Optional)

### 9.1 Test Webhook Endpoint

Use curl to test your webhook endpoint:

```bash
curl -X POST https://[your-org].my.salesforce.com/services/apexrest/githubwebhook \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -H "X-Hub-Signature-256: sha256=test" \
  -d '{"zen": "Keep it simple."}'
```

### 9.2 Monitor Webhook Deliveries

In GitHub App settings:

1. Click **Advanced** tab
2. View **Recent Deliveries**
3. Check for successful deliveries (200 response)

## 📊 Step 10: Production Checklist

Before going to production, verify:

- [ ] GitHub App is configured with correct permissions
- [ ] Webhook secret is strong and randomly generated
- [ ] Private key is stored securely (consider external secret manager)
- [ ] Custom Metadata visibility is set to "Protected"
- [ ] Permission set assigned only to necessary users
- [ ] Debug logs tested and working
- [ ] Webhook deliveries tested and verified
- [ ] Error handling tested (wrong credentials, network issues)
- [ ] Rate limiting considered (GitHub API has limits)
- [ ] Token caching implemented (optional, but recommended)

## 🔄 Step 11: Ongoing Maintenance

### Rotate Private Keys

Recommended every 90 days:

1. Generate new private key in GitHub App settings
2. Convert to base64
3. Update Custom Metadata record
4. Revoke old key in GitHub after verifying new key works

### Monitor API Usage

- GitHub API rate limits: 5,000 requests/hour for installation tokens
- Monitor via GitHub App settings → Advanced tab

### Update Webhook URL

If your Salesforce org URL changes:

1. Update webhook URL in GitHub App settings
2. Update Named Credential in Salesforce (if needed)

## 🆘 Troubleshooting

### Issue: "GitHub App Settings not found"

**Solution:**

- Check Custom Metadata record Developer Name matches: `salesforce_gforce_devhub`
- Verify Permission Set is assigned

### Issue: "Failed to generate JWT"

**Solution:**

- Verify private key is base64 encoded without headers/footers
- Check for extra whitespace or line breaks
- Ensure App ID is correct

### Issue: "401 Unauthorized" from GitHub

**Solution:**

- Verify App ID matches GitHub App
- Verify Installation ID is correct
- Check GitHub App is installed on target repository
- Verify private key is correct

### Issue: "Webhook signature invalid"

**Solution:**

- Verify webhook secret in Custom Metadata matches GitHub App
- Check for typos or extra whitespace
- Ensure webhook secret hasn't been regenerated in GitHub

### Issue: No workflows appearing

**Solution:**

- Verify repository has `.github/workflows/*.yml` files
- Check GitHub App has Actions permissions
- Verify repository name and owner are correct

### Issue: Cannot upload GitHub key as Salesforce certificate

**This is expected!** GitHub App private keys are in PKCS#1/PKCS#8 format, not X.509 certificates.

**Why this doesn't work:**

```
GitHub provides: RSA Private Key (PKCS#1)
Salesforce needs: X.509 Certificate with chain
```

**Solution: Use Protected Custom Metadata instead**

- Convert key to base64 (as shown in Step 2.2)
- Store in Custom Metadata Type field
- This provides equivalent security without format conversion issues

**What happens if you try:**

```bash
# This will fail:
Setup → Certificate and Key Management → Import Certificate
→ Upload github-app-private-key.pem
❌ Error: "Invalid certificate format" or "Missing certificate chain"
```

**Correct approach:**

```bash
# Convert to base64 for Custom Metadata
cat github-app-private-key.pem | grep -v "BEGIN\|END" | tr -d '\n'
→ Store in Custom Metadata Type: GitHub_App_Settings__mdt
✅ Works perfectly!
```

## 📚 Additional Resources

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps)
- [Installing GitHub Apps](https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app)
- [Salesforce Named Credentials](https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm)
- [Protected Custom Metadata Types](https://help.salesforce.com/s/articleView?id=sf.custommetadatatypes_overview.htm)

## 🎉 Success!

You've successfully configured the GitHub Actions integration! You can now:

- ✅ Trigger GitHub workflows from Salesforce
- ✅ Receive webhook notifications when workflows complete
- ✅ Use secure JWT-based authentication
- ✅ Monitor all integration activity

---

**[← Back to Overview](./README.md)** | **[Security Best Practices →](./SECURITY.md)**
