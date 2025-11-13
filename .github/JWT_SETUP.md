# GitHub Actions JWT Authentication Setup

This guide explains how to set up JWT authentication for automated Salesforce deployments in GitHub Actions.

## 🔐 Required GitHub Secrets

You need to configure these secrets in your GitHub repository:

### 1. DEVHUB_JWT_KEY
**Description:** Private key for JWT authentication  
**Format:** Multi-line string containing the RSA private key

```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
(your private key content)
...
-----END RSA PRIVATE KEY-----
```

### 2. DEVHUB_USERNAME
**Description:** Username of the Dev Hub user  
**Format:** email@domain.com  
**Example:** `devhub@mycompany.com`

### 3. DEVHUB_CLIENT_ID
**Description:** Consumer Key from Connected App  
**Format:** Long alphanumeric string  
**Example:** `3MVG9A2kN3Bn17hs...`

### 4. DEVHUB_INSTANCE_URL
**Description:** Salesforce instance URL  
**Format:** https://login.salesforce.com (or custom domain)  
**Examples:** 
- Production: `https://login.salesforce.com`
- Sandbox: `https://test.salesforce.com`
- My Domain: `https://mydomain.my.salesforce.com`

## 🛠️ Setup Steps

### Step 1: Generate Certificate and Private Key

```bash
# Generate private key
openssl genrsa -out server.key 2048

# Generate certificate signing request
openssl req -new -key server.key -out server.csr

# Generate self-signed certificate (valid for 1 year)
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt
```

### Step 2: Create Connected App in Salesforce

1. **Navigate to Setup** → App Manager
2. **Click "New Connected App"**
3. **Fill Basic Information:**
   - Connected App Name: `GitHub Actions CI/CD`
   - API Name: `GitHub_Actions_CI_CD`
   - Contact Email: your-email@domain.com

4. **Enable OAuth Settings:**
   - ✅ Enable OAuth Settings
   - Callback URL: `http://localhost:1717/OauthRedirect`
   - Use digital signatures: ✅ Upload `server.crt` file
   
5. **Selected OAuth Scopes:**
   - Access and manage your data (api)
   - Perform requests on your behalf at any time (refresh_token, offline_access)
   - Access your basic information (id, profile, email, address, phone)

6. **Save and Continue**

### Step 3: Configure Connected App Policies

1. **Edit the Connected App**
2. **OAuth Policies:**
   - Permitted Users: `Admin approved users are pre-authorized`
   - IP Relaxation: `Relax IP restrictions`

3. **Manage Profiles/Permission Sets:**
   - Assign to System Administrator profile
   - Or create dedicated permission set for CI/CD

### Step 4: Configure GitHub Secrets

1. **Go to Repository** → Settings → Secrets and Variables → Actions
2. **Add New Repository Secrets:**

```bash
DEVHUB_JWT_KEY:
# Content of server.key file
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----

DEVHUB_USERNAME:
# Your Dev Hub username
devhub@mycompany.com

DEVHUB_CLIENT_ID:
# Consumer Key from Connected App
3MVG9A2kN3Bn17hs...

DEVHUB_INSTANCE_URL:
# Salesforce instance URL
https://login.salesforce.com
```

### Step 5: Test Authentication

```bash
# Test locally (optional)
sf org login jwt \
  --username "devhub@mycompany.com" \
  --jwt-key-file server.key \
  --client-id "3MVG9A2kN3Bn17hs..." \
  --alias devhub \
  --set-default-dev-hub
```

## 🔄 Workflow Triggers

The workflow runs on:

### Pull Requests
- Target branches: `main`, `develop`
- Changed paths: `weather-app/**`, `apex-common/**`, `apex-mocks/**`, etc.

### Feature Branches
- Branch patterns: `feature/*`, `bugfix/*`, `hotfix/*`
- Changed paths: Any Salesforce metadata

## 🎯 Validation Steps

1. **🔄 Checkout Code** - Get latest source
2. **🔧 Install Salesforce CLI** - Setup tools
3. **🔑 JWT Authentication** - Login to Dev Hub
4. **🧪 Create Scratch Org** - Spin up test environment
5. **📤 Deploy Source** - Push weather-app code
6. **🔐 Assign Permissions** - Setup access
7. **🧩 Run Tests** - Execute Apex tests
8. **🔍 Validate Metadata** - Check deployment
9. **🧹 Cleanup** - Delete scratch org

## 📊 Success Criteria

✅ **Passing Validation:**
- Scratch org creation succeeds
- All source deploys without errors
- Permission set assignment works
- All Apex tests pass
- Metadata validation passes
- Code quality checks pass (ESLint, Prettier)

❌ **Failing Validation:**
- Compilation errors
- Test failures
- Deployment issues
- Code quality violations

## 🚀 Benefits

- **🔒 Secure:** JWT authentication with encrypted secrets
- **⚡ Fast:** Automated validation in ~5-10 minutes
- **🎯 Focused:** Only runs on relevant file changes
- **📝 Informative:** Detailed PR comments and summaries
- **🧹 Clean:** Automatic cleanup of resources
- **📊 Trackable:** Test results and artifacts stored

## 🔧 Troubleshooting

### Common Issues:

1. **"Not a Dev Hub"**
   - Enable Dev Hub in org settings
   - Verify user has Dev Hub permissions

2. **JWT Authentication Failed**
   - Check private key format (includes headers/footers)
   - Verify Connected App consumer key
   - Confirm certificate upload in Connected App

3. **Scratch Org Creation Failed**
   - Check Dev Hub limits (daily/active orgs)
   - Verify scratch org definition file

4. **Permission Issues**
   - Ensure Connected App has proper profiles assigned
   - Check OAuth policies configuration

### Debug Commands:

```bash
# Check auth status
sf org list

# Test scratch org creation locally
sf org create scratch --definition-file config/project-scratch-def.json --alias test

# Validate deployment locally
sf project deploy validate --source-dir weather-app
```

## 📚 Additional Resources

- [Salesforce CLI JWT Auth](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_jwt_flow.htm)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Connected Apps](https://help.salesforce.com/s/articleView?id=sf.connected_app_create.htm)