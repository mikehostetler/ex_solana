# Notification System Plan

**Inspiration:** Novu (enterprise notification infrastructure)  
**Framework:** Ash Framework + ash_oban + Phoenix PubSub  
**Scope:** Database-backed, multi-channel (in-app, email → extensible), template-driven

## Architecture Overview

### Domain Structure
**New Domain:** `JidoHub.Notifications` (Ash.Domain)

**Resources:**
1. `Template` - Event-driven notification templates (global or org-specific)
2. `Preference` - Per-user, per-channel notification settings
3. `Notification` - Logical notification instance for one recipient
4. `Delivery` - Per-channel delivery attempt with status tracking

**Multitenancy:** Attribute strategy on `organization_id` (consistent with existing domains)

## Data Model

### Template (notifications_templates)
```elixir
- id: uuid
- key: string, required (e.g., "pod.created", "org.invite.sent")
- organization_id: uuid | nil (nil = global default)
- name: string
- description: string
- variables: {:array, :string} (required variable names)
- channels: {:array, :atom} (default enabled channels)
- channel_configs: :map (jsonb)
  %{
    in_app: %{title: string, body_text: string},
    email: %{subject: string, body_text: string, body_html: string}
  }
- enabled: boolean, default: true
- timestamps

# Relationships
belongs_to :organization → Organizations.Organization

# Indexes
unique: (organization_id, key)
unique: (NULL, key) for global templates
gin: channel_configs
```

### Preference (notifications_preferences)
```elixir
- id: uuid
- user_id: uuid, required
- organization_id: uuid, required
- channel: atom (enum: :in_app | :email | :sms | :push)
- template_key: string | nil (nil = channel-wide)
- enabled: boolean, default: true
- settings: :map (reserved for future: quiet_hours, digest)
- timestamps

# Relationships
belongs_to :user → Accounts.User
belongs_to :organization → Organizations.Organization

# Indexes
unique: (organization_id, user_id, channel, template_key)
```

### Notification (notifications)
```elixir
- id: uuid
- organization_id: uuid, required
- pod_id: uuid | nil
- recipient_user_id: uuid, required
- template_key: string, required (snapshot reference)
- payload: :map (template variables)
- context: :map (metadata: actor_id, source_resource, etc.)
- overall_status: atom (enum: :pending | :partially_sent | :sent | :failed)
- timestamps

# Relationships
belongs_to :organization → Organizations.Organization
belongs_to :pod → Pods.Pod
belongs_to :recipient_user → Accounts.User
has_many :deliveries → Notifications.Delivery

# Indexes
(recipient_user_id, inserted_at DESC)
(organization_id, inserted_at DESC)

# Notifier
Ash.Notifier.PubSub, topic: "notifications:user:#{recipient_user_id}"
```

### Delivery (notifications_deliveries)
```elixir
- id: uuid
- notification_id: uuid, required
- channel: atom (enum)
- status: atom (enum: :pending | :enqueued | :sent | :failed | :read | :clicked | :bounced)
- last_error: string
- error_meta: :map
- provider_message_id: string
- provider_response: :map
- scheduled_at: utc_datetime
- sent_at: utc_datetime
- read_at: utc_datetime
- clicked_at: utc_datetime
- failed_at: utc_datetime
- attempt: integer, default: 0
- max_attempts: integer, default: 5
- rendered: :map (snapshot of rendered content)
  %{
    title: string,
    text: string,
    html: string
  }
- timestamps

# Relationships
belongs_to :notification → Notifications.Notification

# Indexes
unique: (notification_id, channel)
(status)
(sent_at)
(read_at)

# Notifier
Ash.Notifier.PubSub, topic: "notifications:user:#{notification.recipient_user_id}"
```

## Notification Workflow

### 1. Trigger
```elixir
Notifications.trigger(
  event_key,
  %{
    organization_id: uuid,
    pod_id: uuid | nil,
    recipients: [user_id, ...],
    payload: %{...},
    channels_override: [:in_app, :email] | nil
  }
)
```

### 2. Template Resolution
- Find org-specific Template by key
- Fallback to global Template by key
- Determine active channels: `channels_override || template.channels`

### 3. Preference Resolution
For each `(recipient, channel)`:
```elixir
effective_enabled? = 
  Preference(org, user, channel, template_key) ||
  Preference(org, user, channel) ||
  default(true)
```

### 4. Notification Creation
- Create one `Notification` per recipient
- For each enabled channel, create `Delivery` with status `:pending`
- Change hook: enqueue ash_oban job after Delivery creation

### 5. Dispatch (ash_oban Worker)
```
Worker: JidoHub.Notifications.Workers.DispatchDelivery
Input: %{delivery_id: uuid}

Steps:
1. Load Delivery + Notification + Template (within org tenant)
2. Render content via EEx with payload + context assigns
3. Send via channel adapter (InApp or Email)
4. Update Delivery: status, timestamps, provider IDs
5. Publish via PubSub
6. Update Notification.overall_status (aggregate from deliveries)
```

### 6. In-App Consumption
- Frontend subscribes to `notifications:user:#{user_id}` PubSub topic
- List Notifications via read action filtered by `recipient_user_id`
- Mark read via action: sets `Delivery.read_at` + status `:read`

## Channel Abstraction

### Behaviour: `JidoHub.Notifications.Channel`
```elixir
@callback send(
  delivery :: Delivery.t(),
  notification :: Notification.t(),
  template :: Template.t(),
  context :: map()
) :: {:ok, meta :: map()} | {:error, reason :: term()}

@callback validate_config(config :: map()) :: :ok | {:error, term()}
```

### Registry
Application config: `%{in_app: InAppChannel, email: EmailChannel}`

### Built-in Channels

#### InAppChannel
```elixir
def send(delivery, _notification, _template, _context) do
  # No external provider
  # Status set to :sent
  # Rendered snapshot already stored
  {:ok, %{}}
end
```

#### EmailChannel
```elixir
def send(delivery, notification, _template, _context) do
  # Use existing Swoosh mailer
  # Pass rendered.subject, body_html, body_text
  # Return provider_message_id
  
  %Email{}
  |> to(notification.recipient_user.email)
  |> from("notifications@jidohub.com")
  |> subject(delivery.rendered.subject)
  |> html_body(delivery.rendered.html)
  |> text_body(delivery.rendered.text)
  |> JidoHub.Mailer.deliver()
end
```

### Extensibility
- New channels implement `Channel` behaviour
- Add to application config
- `DispatchDelivery` worker unchanged

## Template System

### EEx-Based Templates
Store template strings per channel variant:
- `in_app`: `title_eex`, `body_text_eex`
- `email`: `subject_eex`, `body_text_eex`, `body_html_eex`

### Variable Substitution
```elixir
# Template variables list
variables: ["user_name", "pod_name", "action_url"]

# Rendering
assigns = 
  payload ++ 
  context ++ 
  %{
    user: recipient_user,
    org: organization,
    pod: pod,
    url: &Routes.helper/1
  }

# Render
title = EEx.eval_string(template.channel_configs.in_app.title, assigns: assigns)
body = EEx.eval_string(template.channel_configs.in_app.body_text, assigns: assigns)

# Store in Delivery.rendered
```

### Validation
- Check `Map.has_key?` for required variables
- Log missing keys
- Fail delivery if hard requirement not met

### Snapshotting
Store rendered content in `Delivery.rendered` for:
- Audit trail
- Consistent re-reads (template changes don't affect past notifications)

## Preference Management

### CRUD Actions
```elixir
# Preference resource
actions do
  create :create do
    accept [:user_id, :organization_id, :channel, :template_key, :enabled]
  end
  
  update :update do
    accept [:enabled, :settings]
  end
  
  destroy :destroy
  
  read :for_user do
    filter expr(user_id == ^arg(:user_id))
  end
end
```

### Upsert Pattern
```elixir
Preference
|> Ash.Changeset.for_create(:upsert, attrs)
|> Ash.create(upsert?: true, upsert_identity: :unique_user_org_channel_template)
```

### Resolution Logic
```elixir
# Service function
def effective_preference?(org_id, user_id, channel, template_key) do
  # 1. Check explicit template preference
  case get_preference(org_id, user_id, channel, template_key) do
    %{enabled: enabled} -> enabled
    nil ->
      # 2. Check channel-wide preference
      case get_preference(org_id, user_id, channel, nil) do
        %{enabled: enabled} -> enabled
        nil -> true  # default enabled
      end
  end
end
```

## Integration with Existing System

### Accounts.User
```elixir
has_many :notifications, JidoHub.Notifications.Notification do
  destination_attribute :recipient_user_id
end

has_many :notification_preferences, JidoHub.Notifications.Preference
```

### Organizations.Organization
```elixir
has_many :notification_templates, JidoHub.Notifications.Template
has_many :notifications, JidoHub.Notifications.Notification
```

### Pods.Pod
```elixir
has_many :notifications, JidoHub.Notifications.Notification
```

### Authorization
**Aligned with AUTHORIZATION_SPEC.md:**

#### Notification/Delivery
- **Read:** recipient user OR org admin (scoped by organization_id tenant)
- **Mark Read:** only recipient user

#### Template
- **Read:** org members (for template-based features)
- **Create/Update/Destroy:** org admin only

#### Preference
- **Read/Update:** user's own preferences OR org admin
- **Create:** user for own preferences

### PubSub Configuration
```elixir
# In Notification resource
pub_sub do
  module JidoHubWeb.Endpoint
  prefix "notifications"
  
  publish :create, ["user", :recipient_user_id]
  publish :update, ["user", :recipient_user_id], event: "updated"
end

# In Delivery resource
pub_sub do
  module JidoHubWeb.Endpoint
  prefix "notifications"
  
  publish :create, ["user", :notification, :recipient_user_id]
  publish :update, ["user", :notification, :recipient_user_id], event: "delivery_updated"
end
```

### ash_oban Integration
```elixir
# In Delivery resource
actions do
  create :create do
    accept [:notification_id, :channel, :scheduled_at]
    change set_attribute(:status, :pending)
    change AshOban.Changes.Enqueue,
      worker: JidoHub.Notifications.Workers.DispatchDelivery,
      args: %{delivery_id: expr(id)},
      scheduled_at: expr(scheduled_at || now())
  end
end

# Worker
defmodule JidoHub.Notifications.Workers.DispatchDelivery do
  use Oban.Worker, queue: :notifications, max_attempts: 5
  
  def perform(%Job{args: %{"delivery_id" => delivery_id}}) do
    # Load delivery with tenant
    # Render template
    # Send via channel
    # Update delivery status
    # Publish via PubSub
  end
end
```

## Implementation Phases

### Phase 1: MVP (1-2 days)
**Scope:** Basic notification flow with in-app + email

- [ ] Create Notifications domain with 4 resources
- [ ] Implement Postgres migrations with multitenancy
- [ ] Build `trigger/1` service function
- [ ] Implement template lookup (org-specific fallback to global)
- [ ] Implement preference resolution (channel-wide only)
- [ ] Create Notification + Delivery records on trigger
- [ ] Build InAppChannel and EmailChannel adapters
- [ ] Implement EEx template rendering
- [ ] Create DispatchDelivery Oban worker
- [ ] Configure PubSub on Notification/Delivery
- [ ] Add `mark_read` action for in-app notifications
- [ ] Basic indexes and constraints

**Deliverable:** Can trigger notifications, render templates, deliver via in-app and email, track status.

### Phase 2: Enhanced Features (1-3 days)
**Scope:** Template variants, per-template preferences, status tracking

- [ ] Template per-channel variants (separate fields)
- [ ] Variables enforcement with validation
- [ ] Rendered snapshot storage
- [ ] Provider message IDs and responses
- [ ] Preferences per template_key
- [ ] User preference management UI/API
- [ ] Delivery status refinements (clicked, bounced)
- [ ] Aggregate Notification.overall_status calculation
- [ ] Error handling and retry logic
- [ ] Metrics and monitoring (Telemetry)

**Deliverable:** Full template system, granular preferences, comprehensive status tracking.

### Phase 3: Advanced Features (1-2 weeks, incremental)
**Scope:** Enterprise-grade features

- [ ] Org-level template overrides with global fallback
- [ ] Template versioning and soft-delete
- [ ] Digest engine (batch multiple notifications)
- [ ] Quiet hours support
- [ ] Per-channel scheduling
- [ ] Additional channels (SMS via Twilio, Push via FCM)
- [ ] Provider webhook ingestion (email opens/clicks/bounces)
- [ ] Advanced targeting (roles, org/pod cohorts)
- [ ] Template preview and testing tools
- [ ] Admin UI for template management
- [ ] Analytics dashboard

**Deliverable:** Enterprise-ready notification infrastructure.

## Technical Decisions & Trade-offs

### ✓ Database-First with ash_oban
**Decision:** One Delivery row = one Oban job  
**Rationale:** Simple, reliable, visible in DB, leverages Ash + Oban strengths  
**Trade-off:** More DB writes vs. in-memory queuing (acceptable for reliability)

### ✓ EEx for Templating
**Decision:** Use EEx.eval_string for template rendering  
**Rationale:** Zero dependencies, native to Elixir, fits ecosystem  
**Trade-off:** Less tooling vs. Liquid/Mustache; code injection risk (mitigate with vetted bindings)  
**Reconsider:** If non-engineers need to edit templates, switch to safer DSL

### ✓ Preference Model: Simple Booleans
**Decision:** Enable/disable per channel/template, settings reserved for future  
**Rationale:** MVP simplicity, extensible via settings jsonb field  
**Trade-off:** Can't do complex preferences now (digest, quiet hours) but easy to add later

### ✓ One Notification Per Recipient Per Event
**Decision:** Separate Notification for each recipient, multiple Deliveries per Notification  
**Rationale:** Clean audit trail, easy retry semantics, clear status per user  
**Trade-off:** More rows vs. shared Notification (acceptable, proper modeling)

### ✓ Multitenancy via organization_id
**Decision:** Attribute multitenancy on organization_id  
**Rationale:** Consistent with existing domains, simple query scoping  
**Trade-off:** Must ensure tenant set on every query (test coverage critical)

### ✓ PubSub for Real-time
**Decision:** Phoenix.PubSub for in-app notification delivery  
**Rationale:** Built-in, reliable, integrates with LiveView  
**Trade-off:** Requires WebSocket connection; fallback to polling for disconnected clients

## Security & Reliability

### Template Safety
- **Risk:** EEx can execute arbitrary code
- **Mitigation:** 
  - Only `EEx.eval_string` with vetted bindings
  - No access to dangerous modules
  - Sanitize HTML output
  - Template editing restricted to org admins

### Multitenancy Enforcement
- **Risk:** Cross-tenant data leaks
- **Mitigation:**
  - Set tenant on every query
  - Integration tests per org
  - Policy checks at resource level

### Email Provider Backpressure
- **Risk:** Provider rate limits or failures
- **Mitigation:**
  - Oban retries with exponential backoff
  - Cap max_attempts (5 default)
  - Alert on repeated failures
  - Circuit breaker pattern for external calls

### Preference Compliance
- **Risk:** GDPR/CCPA violations if users can't opt out
- **Mitigation:**
  - Default to enabled (opt-out model)
  - Clear UX for preference management
  - Respect preferences before delivery
  - Audit trail via Delivery records

### PubSub Data Leaks
- **Risk:** Broadcasting sensitive data to wrong users
- **Mitigation:**
  - Scope topics per user (`notifications:user:#{id}`)
  - Only broadcast IDs, not full payloads
  - Policies on read actions

## Extension Points

### Adding New Channels
1. Implement `JidoHub.Notifications.Channel` behaviour
2. Add module to application config
3. Update Template.channel_configs schema for new channel
4. No changes to core workflow

### Custom Template Engines
1. Define `JidoHub.Notifications.TemplateEngine` behaviour
2. Swap EEx renderer with custom implementation
3. Maintain same rendering interface

### Event-Driven Architecture
1. Existing domains emit events via Ash.Notifier.PubSub
2. Notification system subscribes to topics
3. Maps events to notification triggers automatically

### Webhook Integrations
1. Add provider webhook endpoints
2. Update Delivery status based on provider callbacks
3. Verify signatures, process async

## Monitoring & Observability

### Metrics (Telemetry)
- `notifications.triggered.count`
- `notifications.delivery.sent.count` (per channel)
- `notifications.delivery.failed.count` (per channel)
- `notifications.delivery.latency` (trigger to sent)
- `notifications.preference.opted_out.count`

### Logging
- Template resolution failures
- Missing required variables
- Provider send failures
- Preference evaluation

### Alerts
- High delivery failure rate
- Provider API errors
- Rendering errors
- Queue depth warnings

## Example Usage

### Triggering a Notification
```elixir
# From Organization invitation flow
Notifications.trigger(
  "org.invite.sent",
  %{
    organization_id: org.id,
    recipients: [invitee.id],
    payload: %{
      org_name: org.name,
      inviter_name: actor.username,
      accept_url: invitation_url
    },
    context: %{
      actor_id: actor.id,
      invitation_id: invitation.id
    }
  }
)
```

### Creating a Template
```elixir
Template
|> Ash.Changeset.for_create(:create, %{
  key: "pod.created",
  organization_id: nil,  # global
  name: "Pod Created",
  description: "Sent when a new pod is created",
  variables: ["pod_name", "creator_name", "pod_url"],
  channels: [:in_app, :email],
  channel_configs: %{
    in_app: %{
      title: "New Pod: <%= @pod_name %>",
      body_text: "<%= @creator_name %> created a new pod. Check it out!"
    },
    email: %{
      subject: "New Pod Created: <%= @pod_name %>",
      body_text: "Hi, <%= @creator_name %> just created <%= @pod_name %>. Visit: <%= @pod_url %>",
      body_html: "<p>Hi, <strong><%= @creator_name %></strong> just created <strong><%= @pod_name %></strong>.</p><p><a href=\"<%= @pod_url %>\">Visit Pod</a></p>"
    }
  }
})
|> Ash.create!()
```

### Managing Preferences
```elixir
# Disable email notifications for a specific template
Preference
|> Ash.Changeset.for_create(:upsert, %{
  user_id: user.id,
  organization_id: org.id,
  channel: :email,
  template_key: "pod.created",
  enabled: false
})
|> Ash.create!(upsert?: true)

# Disable all SMS notifications
Preference
|> Ash.Changeset.for_create(:upsert, %{
  user_id: user.id,
  organization_id: org.id,
  channel: :sms,
  template_key: nil,
  enabled: false
})
|> Ash.create!(upsert?: true)
```

### Frontend: Subscribe to Notifications
```javascript
// LiveView hook
const NotificationHook = {
  mounted() {
    this.channel = this.pushEvent("subscribe_notifications", {})
    
    window.addEventListener("phx:notification_created", (e) => {
      // Show toast or update notification bell
      this.updateNotificationBadge()
    })
  }
}
```

## Success Metrics

### MVP Success
- Can trigger notifications from any domain
- Templates render correctly with variables
- In-app notifications delivered in < 1s
- Emails delivered in < 30s
- Users can view notification history
- Users can mark notifications as read

### Phase 2 Success
- Users can manage preferences per channel
- 95%+ delivery success rate
- Status tracking accurate across all channels
- Template variables validated before sending

### Phase 3 Success
- Support 3+ channels (in-app, email, SMS)
- Template override hierarchy works (org → global)
- Digest batching reduces email volume by 50%
- Provider webhook integration tracks opens/clicks
- Admin UI for template management functional
