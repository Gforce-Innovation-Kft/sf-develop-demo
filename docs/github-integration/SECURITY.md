# Security Best Practices - GitHub Actions Integration

Comprehensive security implementation guide for production deployment.

## 🔒 Security Overview

This integration implements multiple layers of security to protect sensitive credentials and ensure secure communication between Salesforce and GitHub.

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Security Layers                          │
├─────────────────────────────────────────────────────────────┤
│ 1. Protected Custom Metadata (Salesforce Platform)          │
│ 2. JWT Token (10-minute expiry, RSA-SHA256)                │
│ 3. Installation Token (1-hour expiry, scoped permissions)   │
│ 4. Named Credentials (Endpoint management, SSL/TLS)         │
│ 5. HMAC-SHA256 Webhook Verification (Payload integrity)     │
│ 6. Permission Sets (Access control)                          │
└─────────────────────────────────────────────────────────────┘
```

## 🛡️ Security Features

### 1. Protected Custom Metadata Type

**Implementation:**

```xml
<!-- GitHub_App_Settings__mdt -->
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <visibility>Protected</visibility>
</CustomObject>
```

**Benefits:**

- ✅ Not accessible through standard API calls
- ✅ Not visible in UI to standard users
- ✅ Only accessible through Apex code
- ✅ Requires explicit permission set assignment
- ✅ Audit trail through Setup Audit Trail

**Access Control:**

```apex
// Only code with proper permissions can access
GitHub_App_Settings__mdt settings = [
    SELECT App_Id__c, Installation_Id__c, Private_Key_Base64__c
    FROM GitHub_App_Settings__mdt
    WHERE DeveloperName = 'salesforce_gforce_devhub'
    LIMIT 1
];
```

### 2. JWT Token Security

**Token Characteristics:**

- ⏱️ **Expiry:** 10 minutes maximum (GitHub limit)
- 🔐 **Algorithm:** RSA-SHA256
- 🎯 **Scope:** Bound to specific GitHub App ID
- 🔄 **Usage:** Single-use, generated fresh for each request

**Implementation:**

```apex
private static String generateJWT(String appId, String privateKeyBase64) {
    Map<String, Object> header = new Map<String, Object>{
        'alg' => 'RS256',
        'typ' => 'JWT'
    };

    Long issuedAt = DateTime.now().getTime() / 1000;
    Long expiresAt = issuedAt + 600; // 10 minutes

    Map<String, Object> payload = new Map<String, Object>{
        'iat' => issuedAt,
        'exp' => expiresAt,
        'iss' => appId
    };

    // Sign with private key
    return signJWT(header, payload, privateKeyBase64);
}
```

**Security Considerations:**

- 🚫 Never log or expose JWT tokens
- 🚫 Don't cache JWT tokens (generate fresh each time)
- ✅ Validate expiration on every use
- ✅ Use strong RSA keys (2048 or 4096 bits)

### 3. Installation Token Security

**Token Characteristics:**

- ⏱️ **Expiry:** 1 hour
- 🎯 **Scope:** Repository-specific, limited permissions
- 🔄 **Refresh:** Automatic with new JWT
- 📝 **Permissions:** Only what's explicitly granted (Actions: write, Contents: read)

**Caching Strategy (Recommended):**

```apex
public static String getInstallationToken() {
    // Check cache first (50-minute TTL for safety)
    String cachedToken = (String)Cache.Org.get('github_installation_token');
    if (cachedToken != null) {
        return cachedToken;
    }

    // Generate new token
    String jwt = generateJWT();
    String installationToken = exchangeJWTForToken(jwt);

    // Cache for 50 minutes (10-minute buffer before expiry)
    Cache.Org.put('github_installation_token', installationToken, 3000);

    return installationToken;
}
```

**Benefits:**

- ✅ Reduces API calls to GitHub
- ✅ Improves performance
- ✅ Stays within rate limits
- ✅ Automatic expiry handling

### 4. Named Credentials

**Configuration:**

```xml
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <endpoint>https://api.github.com</endpoint>
    <label>GitHub API</label>
    <principalType>Anonymous</principalType>
    <protocol>Password</protocol>
</NamedCredential>
```

**Security Benefits:**

- ✅ No hardcoded URLs in code
- ✅ Centralized endpoint management
- ✅ Automatic SSL/TLS enforcement
- ✅ Automatic CORS handling
- ✅ Remote Site Settings managed automatically

**Usage:**

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:GitHub_API/repos/owner/repo/actions/workflows');
req.setMethod('GET');
req.setHeader('Authorization', 'Bearer ' + installationToken);
```

### 5. Webhook Signature Verification

**HMAC-SHA256 Implementation:**

```apex
private static Boolean verifySignature(String payload, String signature, String secret) {
    // GitHub sends: X-Hub-Signature-256: sha256=<hex_digest>
    String expectedSignature = 'sha256=' +
        EncodingUtil.convertToHex(
            Crypto.generateMac('hmacSHA256',
                Blob.valueOf(payload),
                Blob.valueOf(secret)
            )
        );

    return signature == expectedSignature;
}
```

**Security Flow:**

```
GitHub Webhook → Salesforce
                   ↓
            Extract X-Hub-Signature-256
                   ↓
         Calculate HMAC-SHA256(payload, secret)
                   ↓
              Compare signatures
                   ↓
         Match? → Process | Reject → Return 401
```

**Protection Against:**

- ✅ Man-in-the-middle attacks
- ✅ Replay attacks
- ✅ Payload tampering
- ✅ Unauthorized webhook sources

### 6. Permission Set Security

**Principle of Least Privilege:**

```xml
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>GitHub Integration Admin</label>
    <hasActivationRequired>false</hasActivationRequired>
    
    <!-- Custom Metadata Type Access -->
    <customMetadataTypeAccesses>
        <enabled>true</enabled>
        <name>GitHub_App_Settings__mdt</name>
    </customMetadataTypeAccesses>
    
    <!-- Apex Class Access -->
    <classAccesses>
        <apexClass>GitHubAppAuthService</apexClass>
        <enabled>true</enabled>
    </classAccesses>
</PermissionSet>
```

**Best Practices:**

- ✅ Assign only to users who need to trigger workflows
- ✅ Regular review of permission set assignments
- ✅ Remove access when no longer needed
- ✅ Use profiles + permission sets for granular control

## 🔐 Credential Storage

### Current: Protected Custom Metadata

**Why This Approach?**

This integration uses **Protected Custom Metadata** to store the GitHub App private key instead of Salesforce External Credentials or Certificate/Key Pairs. Here's why:

#### ❌ External Credentials (Not Compatible)

**Technical Limitation:**
Salesforce External Credentials with certificate authentication require:

- X.509 certificate format (`.crt` or `.cer`)
- Complete certificate chain
- Certificate metadata (issuer, subject, validity period)

**GitHub App Private Keys:**

- Provided in PKCS#1 or PKCS#8 format (`.pem`)
- Standalone RSA private keys (no certificate wrapper)
- No issuer or certificate chain
- Self-signed by GitHub for your app only

**The Problem:**

```bash
# GitHub provides this:
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----

# Salesforce requires this:
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAKL...  # X.509 certificate
-----END CERTIFICATE-----
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0...  # With certificate context
-----END PRIVATE KEY-----
```

**Why Conversion Fails:**

1. **No Certificate Authority**: GitHub keys aren't issued by a CA
2. **Self-Signed Limitations**: Converting to self-signed cert loses GitHub's signature
3. **Format Mismatch**: Salesforce expects PKCS#12 or JKS, not raw PEM
4. **Metadata Missing**: No subject, issuer, or validity period in GitHub keys

**Attempted Workarounds (All Failed):**

```bash
# Attempt 1: Convert to PKCS#8
openssl pkcs8 -topk8 -inform PEM -outform PEM \
  -in github-key.pem -out pkcs8.pem -nocrypt
# Result: Still not X.509 certificate

# Attempt 2: Create self-signed certificate
openssl req -new -x509 -key github-key.pem -out cert.pem -days 365
# Result: Changes key signature, GitHub rejects it

# Attempt 3: Create PKCS#12 bundle
openssl pkcs12 -export -out keystore.p12 \
  -inkey github-key.pem -in cert.pem
# Result: Salesforce import fails (missing certificate chain)
```

#### ✅ Protected Custom Metadata (Recommended Solution)

**Pros:**

- ✅ Built-in Salesforce feature
- ✅ Protected visibility restricts access
- ✅ No additional infrastructure needed
- ✅ Easy to deploy and manage
- ✅ Audit trail through Setup Audit Trail

**Cons:**

- ⚠️ No field-level encryption (Custom Metadata limitation)
- ⚠️ Visible to system administrators
- ⚠️ Included in change sets and metadata backups

### Enhanced: External Secret Management

For enterprise production environments, consider using external secret managers:

#### Option 1: Named Credentials with AWS Secrets Manager

**Architecture:**

```
Salesforce → Named Credential → AWS API Gateway → Secrets Manager
```

**Implementation:**

```apex
public class SecureCredentialService {
  public static String getPrivateKey() {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:AWS_Secrets_Manager/github-private-key');
    req.setMethod('GET');

    Http http = new Http();
    HttpResponse res = http.send(req);

    Map<String, Object> secret = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    return (String) secret.get('privateKey');
  }
}
```

#### Option 2: HashiCorp Vault

**Architecture:**

```
Salesforce → Named Credential → Vault API → Encrypted Secret
```

**Benefits:**

- ✅ Secrets never stored in Salesforce
- ✅ Centralized secret rotation
- ✅ Additional audit logging
- ✅ Encryption at rest and in transit
- ✅ Fine-grained access policies

#### Option 3: Salesforce Shield Platform Encryption

**Note:** Custom Metadata Types don't support Platform Encryption. Alternative approach:

```apex
// Store encrypted credentials in Custom Object
public class EncryptedCredentialService {
  public static String getPrivateKey() {
    Encrypted_Credential__c cred = [
      SELECT Private_Key_Encrypted__c
      FROM Encrypted_Credential__c
      WHERE Name = 'GitHub_App'
      LIMIT 1
    ];
    return cred.Private_Key_Encrypted__c; // Automatically decrypted
  }
}
```

## 🔄 Key Rotation

### Recommended Schedule

| Credential             | Rotation Frequency | Priority |
| ---------------------- | ------------------ | -------- |
| **Private Key**        | Every 90 days      | High     |
| **Webhook Secret**     | Every 180 days     | Medium   |
| **JWT Token**          | Auto (10 min)      | N/A      |
| **Installation Token** | Auto (1 hour)      | N/A      |

### Private Key Rotation Process

**Step 1: Generate New Key**

```bash
# In GitHub App settings
GitHub App → Private keys → Generate a private key
```

**Step 2: Convert to Base64**

```bash
cat new-private-key.pem | grep -v "BEGIN\|END" | tr -d '\n' > new_key_base64.txt
```

**Step 3: Update Salesforce**

```
Setup → Custom Metadata Types → GitHub App Settings → Edit Record
→ Update Private_Key_Base64__c field
```

**Step 4: Test**

```apex
// Test connection with new key
GitHubActionsService.listWorkflows('owner', 'repo');
```

**Step 5: Revoke Old Key**

```
GitHub App → Private keys → Revoke old key
```

### Webhook Secret Rotation

**Step 1: Generate New Secret**

```bash
openssl rand -hex 32
```

**Step 2: Update Both Systems Simultaneously**

```
1. Update GitHub App webhook secret
2. Update Salesforce Custom Metadata record
3. Test webhook delivery
```

## 📊 Monitoring & Auditing

### 1. Setup Audit Trail

**Monitor:**

- Custom Metadata record changes
- Permission set assignments
- Apex class modifications

**Access:**

```
Setup → Security → View Setup Audit Trail
Filter by: "GitHub"
```

### 2. Debug Logs

**Enable for integration users:**

```bash
sf apex log set --level DEBUG --apex-code DEBUG
```

**Best Practices:**

- 🚫 Don't log full JWT or installation tokens
- ✅ Log token generation success/failure
- ✅ Log API call results (without sensitive data)
- ✅ Log webhook verification results

### 3. Event Monitoring

**Track (if Event Monitoring enabled):**

- API Usage
- Login events
- Report exports
- Custom Metadata access

### 4. GitHub App Monitoring

**Check regularly:**

```
GitHub App → Advanced → Recent Deliveries
- Webhook delivery success rate
- Response codes
- Failed deliveries
```

## 🚨 Incident Response

### Compromised Private Key

**Immediate Actions:**

1. ⚠️ Revoke key in GitHub App settings
2. 🔄 Generate new private key
3. 📝 Update Salesforce Custom Metadata
4. ✅ Test new key works
5. 📊 Review audit logs for unauthorized access
6. 📧 Notify security team

### Compromised Webhook Secret

**Immediate Actions:**

1. ⚠️ Generate new webhook secret
2. 🔄 Update GitHub App and Salesforce simultaneously
3. ✅ Test webhook delivery
4. 📊 Review recent webhook deliveries for anomalies

### Unauthorized Access Detected

**Investigation Steps:**

1. 📊 Review Setup Audit Trail
2. 📊 Review Debug Logs
3. 📊 Check permission set assignments
4. 🔍 Identify affected users
5. 🚫 Remove unauthorized access
6. 🔄 Rotate all credentials
7. 📧 Document incident

## ✅ Security Checklist

### Development Phase

- [ ] Protected Custom Metadata visibility set
- [ ] Private key stored in base64 format
- [ ] Strong webhook secret generated (32+ characters)
- [ ] Named Credentials configured
- [ ] Permission set created with minimal access
- [ ] Debug logs reviewed (no sensitive data)

### Testing Phase

- [ ] JWT generation tested
- [ ] Installation token exchange tested
- [ ] Webhook signature verification tested
- [ ] Permission set access tested
- [ ] Error handling tested (invalid credentials)
- [ ] Rate limiting tested

### Production Deployment

- [ ] All credentials rotated for production
- [ ] External secret management evaluated
- [ ] Monitoring configured
- [ ] Audit trail enabled
- [ ] Incident response plan documented
- [ ] Key rotation schedule established
- [ ] Backup admin assigned permission set
- [ ] Security review completed

### Ongoing Maintenance

- [ ] Quarterly private key rotation
- [ ] Semi-annual webhook secret rotation
- [ ] Monthly audit trail review
- [ ] Quarterly permission set review
- [ ] Annual security assessment

## 📚 Compliance Considerations

### GDPR / Data Privacy

**Data Stored:**

- GitHub App ID (not personal data)
- Installation ID (not personal data)
- Private key (system credential)
- Webhook secret (system credential)

**Recommendations:**

- Document data flows in privacy policy
- Include in data processing agreements
- Regular access reviews

### SOC 2 / ISO 27001

**Control Implementations:**

- ✅ Access control (permission sets)
- ✅ Encryption in transit (HTTPS/TLS)
- ✅ Audit logging (Setup Audit Trail)
- ✅ Credential rotation (documented process)
- ✅ Least privilege (scoped permissions)

### Industry-Specific

**Financial Services (PCI DSS):**

- Strong cryptography (RSA-2048/4096, SHA-256)
- Key rotation policies
- Access control and logging

**Healthcare (HIPAA):**

- Audit controls
- Access management
- Transmission security

## 🔗 Additional Resources

- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security)
- [Salesforce Security Guide](https://developer.salesforce.com/docs/atlas.en-us.secure_coding_guide.meta/secure_coding_guide/)
- [JWT Best Practices](https://tools.ietf.org/html/rfc8725)
- [HMAC Best Practices](https://tools.ietf.org/html/rfc2104)

---

**[← Back to Overview](./README.md)** | **[← Setup Guide](./SETUP.md)**
