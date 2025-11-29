# Petal Pro Feature Documentation

This directory contains high-level documentation of features extracted from the Petal Pro Phoenix starter kit. Each feature document provides an overview, key capabilities, architecture details, and considerations for adapting into JidoHub.

## Feature Index

### Core User Features
- [Authentication & User Management](feature-authentication-and-user-management.md) - Email/password auth, OAuth (Google/GitHub), registration, login, password reset
- [Two-Factor Authentication](feature-two-factor-auth.md) - TOTP-based 2FA with QR code enrollment
- [Organizations & Multitenancy](feature-organizations-and-multitenancy.md) - Team/org model with membership, roles, and data scoping

### Business Features
- [Billing & Subscriptions](feature-billing-and-subscriptions.md) - Stripe integration for subscriptions, plans, trials, webhooks
- [File Uploads & Media](feature-file-uploads-and-media.md) - LiveView uploads with progress, validation, and metadata
- [Notifications & Email](feature-notifications-and-email.md) - In-app notifications and transactional emails via Swoosh

### Content & Data
- [Content & Markdown](feature-content-and-markdown.md) - Markdown-based CMS/blog with sanitization and slugs
- [Search, Filtering & Pagination](feature-search-filtering-and-pagination.md) - Consistent querying patterns with Flop and query_builder

### Infrastructure
- [Background Jobs & Scheduling](feature-background-jobs-and-scheduling.md) - Oban-based job processing with queues, retries, and cron
- [API & OpenAPI](feature-api-and-openapi.md) - JSON API endpoints with generated OpenAPI/Swagger docs

### UI & Operations
- [UI Components & LiveView](feature-ui-components-and-liveview.md) - Tailwind design system with Petal Components and Heroicons
- [Admin, Monitoring & Telemetry](feature-admin-monitoring-and-telemetry.md) - LiveDashboard, Oban Web, metrics, and operational visibility

### Security & Quality
- [Security & Hardening](feature-security-and-hardening.md) - Auth, sessions, CSRF, CSP, password hashing, ID obfuscation
- [Testing & Quality](feature-testing-and-quality.md) - E2E/unit tests with Wallaby, coverage, linting, security scans

### Advanced
- [AI Integration](feature-ai-integration.md) - LangChain-based AI helpers for text generation and analysis

## Petal Pro Version

Documentation extracted from Petal Pro v3.0.1

## Related Resources

- [Petal Pro Documentation](https://docs.petal.build/petal-pro-documentation/)
- [Petal Components](https://petal.build/)
- Source: `/petal_pro/` directory in this repository

## Adaptation for JidoHub

Each feature document includes an "Adaptation Notes" section with considerations for extracting the feature into JidoHub, particularly around:
- Integration with Ash Framework
- Jido-specific patterns and workflows
- Multi-tenancy and organization models
- API design and extensibility
