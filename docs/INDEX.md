# Documentation Index

Welcome to the Salesforce Development Demo documentation. This portfolio showcases enterprise-grade Salesforce development patterns and integrations.

## 📚 Main Documentation

### Getting Started

- **[Main README](../README.md)** - Project overview, features, and quick start guide

### GitHub Actions Integration

A comprehensive integration between Salesforce and GitHub Actions using secure JWT-based authentication.

| Document                                                                   | Description                                     | Audience                   |
| -------------------------------------------------------------------------- | ----------------------------------------------- | -------------------------- |
| **[Overview & Architecture](./github-integration/README.md)**              | System architecture, components, and data flows | Architects, Developers     |
| **[Setup Guide](./github-integration/SETUP.md)**                           | Step-by-step configuration instructions         | DevOps, Administrators     |
| **[Security Best Practices](./github-integration/SECURITY.md)**            | Security implementation and compliance          | Security Teams, Architects |
| **[Quick Reference](./github-integration/QUICKREF.md)**                    | Commands, snippets, and troubleshooting         | Developers, Support        |
| **[Dispatch Event Framework](./github-integration/DISPATCH_FRAMEWORK.md)** | Structured framework for multiple event types   | Developers, Architects     |

## 🎯 Use Cases

### Trigger CI/CD from Salesforce

Trigger GitHub Actions workflows directly from Salesforce UI to deploy code, run tests, or perform infrastructure tasks.

**Relevant Docs:**

- [Setup Guide](./github-integration/SETUP.md)
- [Quick Reference](./github-integration/QUICKREF.md)

### Receive Workflow Notifications

Get real-time updates in Salesforce when GitHub Actions workflows complete.

**Relevant Docs:**

- [Architecture Overview](./github-integration/README.md#data-flow)
- [Webhook Configuration](./github-integration/SETUP.md#step-9-configure-webhook-testing-optional)

### Enterprise Security Patterns

Implement JWT-based authentication and secure credential management.

**Relevant Docs:**

- [Security Best Practices](./github-integration/SECURITY.md)
- [Authentication Flow](./github-integration/README.md#authentication-flow)

## 🏗️ Architecture Patterns

This project demonstrates:

- ✅ **FinancialForce (fflib) Enterprise Patterns** - Domain, Selector, Service layers
- ✅ **Protected Custom Metadata** - Secure credential storage
- ✅ **Named Credentials** - External API integration
- ✅ **Lightning Web Components** - Modern UI development
- ✅ **JWT Authentication** - Industry-standard security
- ✅ **Webhook Processing** - Real-time event handling
- ✅ **Test Coverage** - Apex mocks and unit testing

## 🔍 Finding What You Need

### By Role

**Salesforce Architect**

1. [Architecture Overview](./github-integration/README.md)
2. [Security Best Practices](./github-integration/SECURITY.md)
3. [Main README](../README.md)

**Salesforce Developer**

1. [Setup Guide](./github-integration/SETUP.md)
2. [Quick Reference](./github-integration/QUICKREF.md)
3. [Architecture Overview](./github-integration/README.md)

**DevOps Engineer**

1. [Setup Guide](./github-integration/SETUP.md)
2. [Quick Reference](./github-integration/QUICKREF.md)
3. [Security Best Practices](./github-integration/SECURITY.md)

**Security Team**

1. [Security Best Practices](./github-integration/SECURITY.md)
2. [Architecture Overview](./github-integration/README.md)
3. [Setup Guide](./github-integration/SETUP.md)

**Business Stakeholder**

1. [Main README](../README.md)
2. [Architecture Overview](./github-integration/README.md)

### By Task

**Setting up the integration**
→ [Setup Guide](./github-integration/SETUP.md)

**Understanding the architecture**
→ [Architecture Overview](./github-integration/README.md)

**Reviewing security implementation**
→ [Security Best Practices](./github-integration/SECURITY.md)

**Finding code examples**
→ [Quick Reference](./github-integration/QUICKREF.md)

**Troubleshooting issues**
→ [Quick Reference - Troubleshooting](./github-integration/QUICKREF.md#-troubleshooting-commands)

## 📦 Project Structure

```
sf-develop-demo/
├── README.md                          # Project overview
├── docs/                              # Documentation root
│   ├── INDEX.md                       # This file
│   └── github-integration/            # GitHub integration docs
│       ├── README.md                  # Architecture overview
│       ├── SETUP.md                   # Setup instructions
│       ├── SECURITY.md                # Security guide
│       └── QUICKREF.md                # Quick reference
├── apex-common/                       # fflib patterns
├── apex-mocks/                        # Testing framework
├── github-action-service/             # GitHub integration package
│   └── main/default/
│       ├── classes/                   # Apex classes
│       ├── lwc/                       # Lightning Web Components
│       └── customMetadata/            # Configuration
├── force-app/                         # Core Salesforce metadata
└── weather-app/                       # Sample application
```

## 🔗 External Resources

### Salesforce

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Apex Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
- [Lightning Web Components Dev Guide](https://developer.salesforce.com/docs/component-library/documentation/en/lwc)

### GitHub

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub REST API](https://docs.github.com/en/rest)

### Security

- [JWT Specification (RFC 7519)](https://tools.ietf.org/html/rfc7519)
- [JWT Best Practices](https://tools.ietf.org/html/rfc8725)
- [HMAC Specification (RFC 2104)](https://tools.ietf.org/html/rfc2104)

## 🤝 Contributing

This is a demonstration project for portfolio purposes. Feel free to use these patterns in your own projects.

## 📄 Version History

| Version | Date     | Changes                                               |
| ------- | -------- | ----------------------------------------------------- |
| 2.0.0   | Dec 2025 | Reorganized documentation, added comprehensive guides |
| 1.0.0   | Nov 2025 | Initial GitHub Actions integration                    |

## 📧 Contact

For questions about this portfolio project, please reach out via GitHub.

---

**[← Back to Main README](../README.md)**
