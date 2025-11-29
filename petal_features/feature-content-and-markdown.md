# Feature: Content and Markdown

## Overview

This feature provides a complete content management system for markdown-based content, primarily implemented as a blog/posts system. It handles the full content lifecycle including creation, editing, publishing, and display with automatic slug generation and HTML sanitization. The markdown rendering pipeline ensures safe, properly formatted content suitable for public display.

The system is designed to be flexible enough to power blogs, knowledge bases, documentation sites, or any content-heavy feature requiring rich text formatting with version control and SEO-friendly URLs.

## Key Capabilities

- Markdown authoring with rich text rendering
- Automatic URL slug generation and uniqueness validation
- HTML sanitization to prevent XSS attacks
- Content CRUD operations with Ash resources
- SEO-friendly URLs and metadata support
- Public and draft content states
- LiveView-based content management interface

## Architecture & Implementation

### Related Modules

- `lib/petal_pro/posts/` - Post resources and business logic
- `lib/petal_pro_web/live/posts/` - LiveViews for content display and management

### Key Dependencies

- `earmark` - Markdown to HTML conversion
- `html_sanitize_ex` - HTML sanitization and XSS prevention
- `slugify` - URL-safe slug generation from titles

## Integration Points

Posts integrate with the authentication system to track authors and control edit permissions. The content rendering pipeline processes markdown through Earmark, then sanitizes output with html_sanitize_ex before display. Slugs are validated for uniqueness at the database level. The LiveView interface provides real-time preview and editing capabilities.

## Adaptation Notes

For JidoHub, consider whether full blog functionality is needed or if a simpler knowledge base structure would suffice. The post schema can be extended with additional fields for categorization, tagging, or custom metadata. The slug generation logic may need adjustment based on URL structure preferences. Ensure proper authorization rules are in place to control who can create and edit content.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation

**Slug Infrastructure:**
- `JidoHub.Slugs` module provides slug resolution for Users, Organizations, and Pods
- Reserved slugs list includes "blog" and "docs" (indicating planned routes)
- Slug generation changes for Organizations and Pods with uniqueness validation
- Custom slug generation in Pod and Organization changes modules

**Dependencies in mix.exs:**
- ✅ `slugify` - Present in mix.lock for URL-safe slug generation
- ✅ `earmark` - Present in mix.lock for markdown to HTML conversion
- ❌ `html_sanitize_ex` - **NOT present** in dependencies

**Content Resources:**
- Pod resource exists with slug-based routing and ownership
- No dedicated Post, Article, or Blog resources
- No markdown rendering pipeline
- No content publishing workflow

### Missing from JidoHub

**Critical Missing Dependencies:**
1. `html_sanitize_ex` - Required for XSS prevention when rendering user-generated markdown
2. No markdown rendering service module

**Missing Core Modules:**
1. **Post/Article Resource** - No Ash resource for blog posts or articles
2. **Markdown Rendering Pipeline** - No service to process markdown → HTML → sanitized output
3. **Content Management Interface** - No LiveViews for creating/editing/publishing content
4. **Publishing Workflow** - No draft/published states or publication date handling
5. **Author Attribution** - No author tracking or byline system
6. **SEO Metadata** - No meta descriptions, Open Graph tags, or structured data
7. **Content Categorization** - No tagging or category system
8. **Content Preview** - No real-time markdown preview during editing

**Missing Integration Points:**
- No authorization policies for content creation/editing
- No content listing views (blog index, archives)
- No permalink routing for individual posts
- No RSS/Atom feed generation

### Implementation Priority

**HIGH Priority:**
1. Add `html_sanitize_ex` dependency (security-critical)
2. Create markdown rendering service module
3. Create Post/Article Ash resource with basic CRUD
4. Implement content authorization policies

**MEDIUM Priority:**
5. Build LiveView interfaces for content management
6. Add publishing workflow (draft/published states)
7. Implement content listing and detail views
8. Add author attribution and metadata

**LOW Priority:**
9. SEO enhancements (meta tags, structured data)
10. Content categorization and tagging
11. RSS feed generation
12. Advanced features (search, related posts, comments)

### Migration Complexity

**MODERATE Complexity**

**Easy Components:**
- ✅ Slug infrastructure already exists and is well-designed
- ✅ `earmark` and `slugify` dependencies already present
- ✅ Ash Framework provides resource scaffolding
- ✅ Authentication system ready for author attribution

**Moderate Components:**
- 🟡 Need to design Post schema compatible with existing Pod/Org structure
- 🟡 Markdown rendering requires custom service module with proper error handling
- 🟡 HTML sanitization configuration needs security review
- 🟡 LiveView interfaces require UI design decisions

**Challenging Components:**
- 🔴 Integration decision: Should content live inside Pods or as standalone resources?
- 🔴 Authorization model: Pod-level vs organization-level vs user-level content permissions
- 🔴 URL structure: Direct routes (/blog/post-slug) vs namespaced (@user/blog/post-slug)
- 🔴 Reserved slug "blog" conflicts with potential dynamic routing

**Estimated Effort:** 3-5 days for basic implementation, 8-12 days for production-ready system

**Risk Factors:**
- Security: HTML sanitization must be properly configured to prevent XSS
- Architecture: Content ownership model needs careful design to align with existing Pods/Orgs
- Performance: Markdown rendering should be cached to avoid repeated processing
