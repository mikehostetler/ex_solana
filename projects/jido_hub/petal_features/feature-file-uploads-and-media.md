# Feature: File Uploads and Media

## Overview
This feature provides a complete file upload system built on Phoenix LiveView's native upload capabilities. It delivers real-time upload progress tracking, client and server-side validation, and automatic metadata extraction. The system is designed with storage abstraction in mind, defaulting to local filesystem storage while supporting migration to cloud providers like S3.

The implementation leverages LiveView's built-in `allow_upload/3` and related upload primitives to handle multipart uploads with minimal JavaScript. Files are validated for type, size, and other constraints before processing, with detailed error feedback surfaced to users through the UI.

## Key Capabilities
- Real-time upload progress with LiveView streams
- Client and server-side file validation (type, size, count)
- Automatic metadata extraction (MIME type, file size, dimensions)
- Storage abstraction layer for flexible backends
- Thumbnail generation and image processing hooks
- Drag-and-drop upload interface

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/file_uploads/` - Core upload logic, storage adapters, metadata handling
- `lib/petal_pro_web/live/uploads/` - LiveView components for upload UI
- `lib/petal_pro_web/components/` - Reusable upload-related components

### Key Dependencies
- `phoenix_live_view` - Native upload functionality and real-time UI
- `sizeable` - Human-readable file size formatting
- `slugify` - Safe filename generation

## Integration Points
The file upload system integrates with user accounts for ownership tracking, storage systems for persistence, and notification systems for upload completion alerts. Upload metadata is typically stored in Ecto schemas, allowing uploads to be associated with any resource in the application (posts, profiles, documents, etc.).

## Adaptation Notes
For JidoHub integration, consider how uploads relate to AI workflows and agent outputs. The storage abstraction layer should be configured early to match deployment infrastructure (local dev, cloud production). Metadata schemas may need extension to track AI-specific attributes like generation timestamps, model versions, or processing status. Consider adding virus scanning and content moderation hooks for user-generated uploads.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation
- **No file upload functionality**: Only a placeholder button exists in [profile_live.ex](file:///Users/mhostetler/Source/Jido/hub/jido_hub/lib/jido_hub_web/live/settings/profile_live.ex#L39-L40) that displays "Avatar upload coming soon"
- **No storage infrastructure**: No local or cloud storage adapters configured
- **No image processing**: No dependencies for image manipulation, thumbnail generation, or validation
- **No metadata extraction**: No modules for capturing file size, MIME types, or image dimensions
- **Static assets only**: Only [priv/static/images/logo.svg](file:///Users/mhostetler/Source/Jido/hub/jido_hub/priv/static/images/logo.svg) exists; no user-uploaded content directory
- **User model incomplete**: User resource lacks avatar_url or image-related attributes (only dashboard Orgs struct has placeholder avatar_url field)
- **Missing dependencies**: No `sizeable`, `slugify`, waffle, arc, or ex_aws_s3 in [mix.exs](file:///Users/mhostetler/Source/Jido/hub/jido_hub/mix.exs)

### Missing from JidoHub
1. **Core upload modules** (`lib/*/file_uploads/`)
   - Storage abstraction layer for local/S3/cloud providers
   - File validation logic (type, size, count constraints)
   - Metadata extraction and persistence
   
2. **LiveView upload components** (`lib/*_web/live/uploads/`)
   - `allow_upload/3` integration
   - `consume_uploaded_entries/3` handlers
   - Real-time progress tracking with streams
   - Drag-and-drop UI components
   
3. **Image processing pipeline**
   - Thumbnail generation
   - Image resizing/optimization
   - EXIF data extraction
   
4. **Storage configuration**
   - Local filesystem paths (priv/static/uploads/)
   - S3/cloud adapter setup for production
   - URL generation for uploaded files
   
5. **Database schema**
   - Upload records table (file_path, size, mime_type, user_id)
   - Association with User, Pod, or other resources
   
6. **Validation & security**
   - File type whitelist/blacklist
   - Size limits
   - Virus scanning hooks
   - Content moderation integration

### Implementation Priority
**HIGH** - File uploads are essential for:
- User profile avatars (already stubbed in UI)
- Organization logos and branding
- Workflow/agent output artifacts (logs, reports, generated files)
- Document management for AI processing pipelines
- Multi-modal AI inputs (images for vision models)

Without this feature, JidoHub lacks basic user personalization and cannot handle file-based workflows, severely limiting AI agent capabilities that need to process or generate files.

### Migration Complexity
**MODERATE** - Implementation pathway:
1. **Simple start** (1-2 days): Add LiveView upload to profile avatar with local storage
   - Use Phoenix LiveView's built-in `allow_upload/3`
   - Store to `priv/static/uploads/avatars/`
   - Add `avatar_url` to User resource
   
2. **Moderate extension** (3-5 days): Abstract storage layer and add validation
   - Create storage module with local/S3 adapters
   - Add file validation (types, sizes)
   - Implement thumbnail generation with image library
   
3. **Full feature parity** (1-2 weeks): Complete Petal Pro functionality
   - Build generic upload components for reuse
   - Add metadata extraction and database records
   - Integrate with Oban for background processing
   - Configure production S3/cloud storage
   - Add virus scanning and content moderation

**Key complexity factors**:
- Phoenix LiveView already provides upload primitives (reduces effort)
- Storage abstraction requires careful design for future cloud migration
- Image processing adds dependency on imagemagick or similar
- Ash framework integration for upload schemas and actions
- Security considerations (validation, scanning) add surface area

**Recommendation**: Start with avatar upload using local storage, then incrementally add storage abstraction and image processing as needed for AI workflow features.
