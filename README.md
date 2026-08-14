# Salesforce Development Demo

A comprehensive Salesforce DX project showcasing enterprise-grade integrations, security best practices, and modern development patterns.

## 🚀 Features

### GitHub Actions Integration

Secure, bidirectional integration between Salesforce and GitHub Actions using GitHub App authentication.

- ✅ **Trigger GitHub workflows** directly from Salesforce
- ✅ **Receive webhook notifications** when workflows complete
- ✅ **JWT-based authentication** (no personal access tokens)
- ✅ **Enterprise security** with Protected Custom Metadata
- ✅ **Visual interface** with Lightning Web Components

**[📖 Read the Complete Documentation →](./docs/github-integration/README.md)**

### Enterprise Architecture Patterns

- **FinancialForce (fflib) Libraries**: Domain, Selector, Service, and Unit of Work patterns
- **Apex Mocks**: Comprehensive mocking framework for unit testing
- **Modular Design**: Organized packages for reusability

### Modern Development Experience

- **DevContainer Support**: Fully configured development environment with Docker
- **CI/CD Pipelines**: GitHub Actions workflows for automated testing and deployment
- **CI**: PR gate — static analysis, then validation in a throwaway scratch org, both delegated to `shared-github-actions`
- **Code Quality Checks**: ESLint and Prettier integration

## 📁 Project Structure

```
sf-develop-demo/
├── fflib-apex-common/    # fflib enterprise patterns (git submodule)
├── fflib-apex-mocks/     # Testing framework (git submodule)
├── force-app/            # Core Salesforce metadata
├── github-action-service/ # GitHub integration package
├── weather-app/          # Sample application
├── docs/                 # Documentation
│   └── github-integration/
│       ├── README.md     # Overview & architecture
│       ├── SETUP.md      # Setup instructions
│       └── SECURITY.md   # Security best practices
└── scripts/              # Automation scripts
```

## 🏃 Quick Start

### Prerequisites

- Salesforce CLI (`sf` command)
- Node.js 18+ (for LWC development)
- Git
- Docker (for DevContainer support)

### Option 1: DevContainer Development (Recommended)

This project includes a complete DevContainer configuration for consistent development environments.

```bash
# Open in VS Code with DevContainers extension
code .
# VS Code will prompt to "Reopen in Container"
```

**Included in DevContainer:**

- ✅ Salesforce CLI pre-installed
- ✅ Node.js 18+ with dependencies
- ✅ Git and essential tools
- ✅ VS Code Salesforce extensions
- ✅ Consistent environment across team

### Option 2: Local Development

### Setup Development Org

```bash
# Create scratch org
./scripts/create_scratch_org.sh

# Deploy all metadata
sf project deploy start

# Assign permissions
sf org assign permset --name GitHub_Integration_Admin
```

### Configure GitHub Integration

1. **Create GitHub App** - Follow the [setup guide](./docs/github-integration/SETUP.md)
2. **Configure credentials** in Custom Metadata Type
3. **Test connection** using the LWC component

## 🛡️ Security Features

- **Protected Custom Metadata**: Credentials secured at platform level
- **JWT Authentication**: Industry-standard server-to-server auth
- **HMAC Webhook Verification**: Ensures payload integrity
- **Named Credentials**: Centralized endpoint management
- **Short-lived Tokens**: 10-minute JWT, 1-hour installation tokens

### Why Not External Credentials?

This integration uses **Protected Custom Metadata** instead of Salesforce External Credentials because:

- ⚠️ **Incompatible Key Format**: GitHub Apps provide private keys in PKCS#1 format, but Salesforce certificates require X.509 format with additional metadata
- ⚠️ **No Certificate Chain**: GitHub's private keys are standalone RSA keys without the certificate chain required by Salesforce
- ⚠️ **Manual Conversion Issues**: Converting GitHub's keys to X.509 certificates requires complex OpenSSL operations that often fail
- ✅ **Better Alternative**: Protected Custom Metadata provides equivalent security while accepting base64-encoded keys directly

See [Security Documentation](./docs/github-integration/SECURITY.md) for details.

## 📚 Documentation

| Document                                                                    | Description                                 |
| --------------------------------------------------------------------------- | ------------------------------------------- |
| [GitHub Integration Overview](./docs/github-integration/README.md)          | Architecture, flows, and component details  |
| [Setup Guide](./docs/github-integration/SETUP.md)                           | Step-by-step configuration                  |
| [Security Best Practices](./docs/github-integration/SECURITY.md)            | Security implementation and recommendations |
| [Dispatch Event Framework](./docs/github-integration/DISPATCH_FRAMEWORK.md) | Structured event dispatching framework      |
| [Quick Reference](./docs/github-integration/QUICKREF.md)                    | Commands, snippets, and troubleshooting     |
| [Weather Demo](./WEATHER_DEMO_README.md)                                    | Sample weather application                  |

## 🔧 Development

### Run Tests

```bash
# Run all tests
sf apex run test --test-level RunLocalTests --wait 10

# Run specific test class
sf apex run test --tests GitHubActionsServiceTest --code-coverage
```

### Deploy to Sandbox

```bash
# Set target org
sf config set target-org your-sandbox-alias

# Deploy
sf project deploy start --source-dir force-app
```

### Debugging

```bash
# Tail logs in real-time
sf apex tail log --color

# View debug logs
sf apex get log --number 1
```

## 📦 Components

### GitHub Integration Package

- **Apex Classes**: `GitHubAppAuthService`, `GitHubActionsService`, `GitHubWebhookService`
- **LWC Component**: `gitHubActionTrigger`
- **Custom Metadata**: `GitHub_App_Settings__mdt`
- **Named Credentials**: `GitHub_API`

### Enterprise Libraries

- **fflib-apex-common**: application framework — git submodule of
  [apex-enterprise-patterns/fflib-apex-common](https://github.com/apex-enterprise-patterns/fflib-apex-common)
- **fflib-apex-mocks**: mocking framework for testing — git submodule of
  [apex-enterprise-patterns/fflib-apex-mocks](https://github.com/apex-enterprise-patterns/fflib-apex-mocks)

Clone with `git clone --recurse-submodules`, or run `git submodule update --init --recursive`
in an existing checkout — the Apex build will not compile without them.

## 🤝 Contributing

This is a demonstration project showcasing enterprise Salesforce development patterns. Feel free to use these patterns in your own projects.

## 📄 License

This project is for demonstration purposes.

## 🔗 Resources

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [JWT Authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)

---

**Built with** ❤️ **for the Salesforce community**
