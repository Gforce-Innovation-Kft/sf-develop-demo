# GitHub Actions Integration

> A secure, bidirectional integration between Salesforce and GitHub Actions using GitHub App authentication with JWT tokens.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Authentication Flow](#authentication-flow)
- [Components](#components)
- [Data Flow](#data-flow)
- [Getting Started](#getting-started)

## Overview

This integration enables Salesforce to:

- 🚀 **Trigger GitHub Actions workflows** directly from the Salesforce UI
- 📨 **Receive webhook notifications** when workflows complete
- 🔒 **Authenticate securely** using GitHub App with JWT tokens (no PATs)
- 🎯 **Fine-grained permissions** at the app level, not user level
- 🔄 **Automatic token refresh** with short-lived credentials

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Salesforce Org                             │
│                                                                      │
│  ┌──────────────────────┐         ┌─────────────────────────────┐  │
│  │  LWC Component       │         │  Custom Metadata Type       │  │
│  │  gitHubActionTrigger │────────▶│  GitHub_App_Settings__mdt   │  │
│  │                      │         │  - App ID                   │  │
│  │  [Test Connection]   │         │  - Installation ID          │  │
│  │  [Trigger Workflow]  │         │  - Private Key (Base64)     │  │
│  └──────────┬───────────┘         │  - Webhook Secret           │  │
│             │                     └─────────────────────────────┘  │
│             │                                                       │
│             ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │              GitHubActionsService                            │  │
│  │  - listWorkflows(owner, repo)                               │  │
│  │  - triggerWorkflow(request)                                 │  │
│  └─────────────────────┬───────────────────────────────────────┘  │
│                        │                                           │
│                        ▼                                           │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │              GitHubAppAuthService                            │  │
│  │  - generateJWT()                                            │  │
│  │  - getInstallationToken()                                   │  │
│  └─────────────────────┬───────────────────────────────────────┘  │
│                        │                                           │
│                        │ Named Credential: GitHub_API             │
│                        ▼                                           │
└────────────────────────┼───────────────────────────────────────────┘
                         │
                         │ HTTPS (JWT/Token Auth)
                         │
                         ▼
┌────────────────────────────────────────────────────────────────────┐
│                         GitHub API                                  │
│  https://api.github.com                                            │
│                                                                     │
│  POST /app/installations/{id}/access_tokens  (JWT Auth)           │
│  GET  /repos/{owner}/{repo}/actions/workflows (Token Auth)        │
│  POST /repos/{owner}/{repo}/actions/workflows/{id}/dispatches     │
│                                                                     │
│  ┌──────────────────┐                                              │
│  │   GitHub App     │                                              │
│  │   Installed on   │                                              │
│  │   Repository     │                                              │
│  └──────────────────┘                                              │
└─────────────────────┬──────────────────────────────────────────────┘
                      │
                      │ Webhook Events
                      │ (HMAC-SHA256 Signature)
                      ▼
┌────────────────────────────────────────────────────────────────────┐
│                    Salesforce REST Endpoint                         │
│  /services/apexrest/githubwebhook                                  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │            GitHubWebhookService                               │ │
│  │  - handleWebhook()                                           │ │
│  │  - verifySignature()                                         │ │
│  │  - handleWorkflowRun()                                       │ │
│  │  - handleWorkflowJob()                                       │ │
│  └──────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

## Authentication Flow

### 1️⃣ JWT Token Generation

```
Salesforce Request → GitHubAppAuthService.generateJWT()
                     ↓
              Read Custom Metadata:
              - App ID (123456)
              - Private Key (RSA-2048/4096)
                     ↓
              Create JWT:
              {
                "alg": "RS256",
                "typ": "JWT",
                "payload": {
                  "iat": <timestamp>,
                  "exp": <timestamp + 10min>,
                  "iss": "<app_id>"
                }
              }
                     ↓
              Sign with RSA-SHA256
                     ↓
              JWT Token (valid 10 minutes)
```

### 2️⃣ Installation Token Exchange

```
POST /app/installations/{id}/access_tokens
Authorization: Bearer <JWT_TOKEN>
                     ↓
GitHub API Returns:
{
  "token": "ghs_xxxxxxxxxxxxx",
  "expires_at": "2025-12-11T16:45:00Z",
  "permissions": {
    "actions": "write",
    "contents": "read"
  }
}
                     ↓
Installation Token (valid 1 hour)
```

### 3️⃣ API Calls with Installation Token

```
GET /repos/{owner}/{repo}/actions/workflows
Authorization: Bearer <INSTALLATION_TOKEN>
                     ↓
Returns: List of workflows
```

## Components

### Apex Classes

| Class                    | Purpose                    | Key Methods                                 |
| ------------------------ | -------------------------- | ------------------------------------------- |
| **GitHubAppAuthService** | JWT & token management     | `generateJWT()`<br>`getInstallationToken()` |
| **GitHubActionsService** | GitHub Actions API calls   | `listWorkflows()`<br>`triggerWorkflow()`    |
| **GitHubWebhookService** | Receive & process webhooks | `handleWebhook()`<br>`verifySignature()`    |

### Metadata Components

| Component                                     | Purpose                                                     |
| --------------------------------------------- | ----------------------------------------------------------- |
| **GitHub_App_Settings\_\_mdt**                | Stores App ID, Installation ID, Private Key, Webhook Secret |
| **GitHub_API** (Named Credential)             | Endpoint configuration for api.github.com                   |
| **GitHub_API** (Remote Site Settings)         | Allow HTTPS callouts to GitHub                              |
| **GitHub_Integration_Admin** (Permission Set) | Grants access to all components                             |
| **gitHubActionTrigger** (LWC)                 | User interface for testing and triggering workflows         |

## Data Flow

### Example: List Workflows

```
1. User clicks "Test Connection" button in LWC
2. LWC calls: listWorkflows({ owner: 'myorg', repo: 'myrepo' })
3. GitHubActionsService.listWorkflows()
4. GitHubAppAuthService.getInstallationToken()
   ├─→ generateJWT() → Returns JWT token
   └─→ POST /app/installations/{id}/access_tokens → Returns installation token
5. GET /repos/myorg/myrepo/actions/workflows
6. Returns: { "total_count": 3, "workflows": [...] }
7. LWC displays workflows in UI
```

### Example: Trigger Workflow

```
1. User clicks "Deploy to Staging" button
2. LWC calls: triggerWorkflow({
     owner: 'myorg',
     repo: 'myrepo',
     workflowId: 'deploy-staging.yml',
     ref: 'main'
   })
3. GitHubActionsService.triggerWorkflow()
4. Gets installation token (cached or refreshed)
5. POST /repos/.../actions/workflows/deploy-staging.yml/dispatches
6. GitHub returns 204 No Content (success)
7. Salesforce shows success toast
8. GitHub Actions workflow starts running
9. On completion, GitHub sends webhook to Salesforce
10. GitHubWebhookService logs the result
```

### Example: Webhook Processing

```
1. GitHub workflow completes
2. GitHub sends POST to /services/apexrest/githubwebhook
3. GitHubWebhookService.verifySignature()
   - Validates HMAC-SHA256 signature
4. GitHubWebhookService.handleWorkflowRun()
   - Parses workflow data
   - Logs to System.debug()
   - (Optional) Creates records or sends notifications
```

## Security Layers

### 🔒 Protected Custom Metadata

- Visibility set to "Protected"
- Only accessible through Apex
- Not exposed through API/UI
- Requires permission set assignment

**Why not External Credentials?**
GitHub App private keys are in PKCS#1/PKCS#8 format (raw RSA keys), but Salesforce External Credentials require X.509 certificates with a complete certificate chain. Converting GitHub's keys to X.509 format is impractical and would break GitHub's signature verification. Protected Custom Metadata accepts the keys in their native format while providing equivalent security.

### 🔑 JWT Token Security

- Short-lived (10 minutes max)
- Signed with RSA-SHA256
- Bound to specific App ID
- Generated fresh for each use

### ⏱️ Installation Token Security

- Short-lived (1 hour)
- Scoped permissions (actions, contents)
- Repository-specific access
- Automatically refreshed

### ✅ Webhook Signature Verification

- HMAC-SHA256 verification
- Shared secret between GitHub & Salesforce
- Prevents replay attacks
- Verifies payload integrity

### 🌐 Named Credentials

- Centralized endpoint management
- Automatic CORS handling
- No hardcoded URLs in code
- SSL/TLS enforced

## Getting Started

### Quick Links

- **[Setup Guide](./SETUP.md)** - Step-by-step configuration instructions
- **[Security Best Practices](./SECURITY.md)** - Security implementation details
- **[API Reference](./API.md)** - Apex class documentation _(coming soon)_

### Prerequisites

1. GitHub App with Actions permissions
2. Salesforce org with Lightning enabled
3. Salesforce CLI installed
4. Basic understanding of JWT authentication

### Next Steps

1. Follow the [Setup Guide](./SETUP.md) to configure your GitHub App
2. Review [Security Best Practices](./SECURITY.md) for production deployment
3. Deploy the package to your Salesforce org
4. Test the integration using the LWC component

## Advantages

✅ **No Personal Access Tokens** - More secure than PATs  
✅ **Fine-grained Permissions** - App-level, not user-level  
✅ **Automatic Token Refresh** - Installation tokens auto-regenerate  
✅ **Audit Trail** - All actions attributed to GitHub App  
✅ **Two-way Communication** - Trigger workflows AND receive status  
✅ **Protected Credentials** - Custom Metadata with Protected visibility  
✅ **Modular Design** - Separate package for easy reuse

## Troubleshooting

### Test Connection

Use the LWC component's "Test Connection & List Workflows" button to verify:

- ✓ Custom Metadata is accessible
- ✓ JWT generation works
- ✓ Installation token retrieval works
- ✓ API connectivity is established
- ✓ Workflows can be listed

### View Debug Logs

```bash
# Real-time logs
sf apex tail log --color

# Or in Salesforce UI: Setup → Debug Logs → View
```

### Common Issues

| Error                           | Solution                                        |
| ------------------------------- | ----------------------------------------------- |
| "GitHub App Settings not found" | Check Custom Metadata record Developer Name     |
| "Failed to generate JWT"        | Verify private key format (base64, no headers)  |
| "401 Unauthorized"              | Check App ID and Installation ID are correct    |
| "Invalid signature"             | Verify webhook secret matches GitHub App config |

## Resources

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [JWT Authentication Guide](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)
- [GitHub Actions API](https://docs.github.com/en/rest/actions)
- [Salesforce Named Credentials](https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm)

---

**[← Back to Main README](../../README.md)**
