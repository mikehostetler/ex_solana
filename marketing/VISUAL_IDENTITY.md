# Jido Visual Identity & Design System

**Purpose:** Visual design guidelines for agentjido.xyz and ecosystem that align with the production-hardened, code-first brand voice.

**Target:** Phoenix/LiveView implementation with dark theme, code-editor aesthetic.

**Core Concept:** *Grafana for agents on the BEAM*—serious, observable, production-first, yet approachable via clean typography and clear diagrams.

---

## Design Principles

### 1. Code-Before-Illustration

- Above the fold: always show real Elixir code + at least one metric strip
- Visual hierarchy: **Code & metrics > Diagrams > Headlines > Decorative elements**
- No generic "SaaS hero" illustrations unless they directly encode supervision/agents
- Code blocks are primary visual elements, not afterthoughts

### 2. Instrumentation Over Vibes

- Use cards, charts, and metric tiles rather than abstract art
- Diagrams should look like architecture notes or supervision trees, not "AI blobs"
- Each major visual tied to a specific claim (agents/node, RAM, latency)
- Screenshots from Observer, dashboards, and telemetry tools

### 3. Minimal, Precise, and Quiet

- Dark background, few accent colors, lots of negative space
- Clear grids, subtle borders, restrained shadows
- Avoid noisy gradients or random shapes
- Treat UI like a tool dashboard, not a marketing site

### 4. Two Mental Models, One Visual Language

- For BEAM natives: show supervision trees, processes, OTP naming
- For migrators: show node/queue/worker diagrams side-by-side with BEAM processes
- Use toggles/tabbed content instead of separate flows
- Consistent visual language across both views

### 5. Evidence-Driven UI

- Metric strips paired with footnotes on test conditions
- Screenshots/visuals annotated with specific numbers ("5,000 agents, 200MB RAM")
- Benchmark graphs with environment specs visible
- Every claim has a visual proof element

### 6. Calm Confidence

- Modest motion: small hover transitions, live-updating charts, gentle glows on active elements
- No bouncing, overshooting animations, or playful mascots
- Transitions: 150-250ms easing, nothing jarring
- LiveView updates should feel natural, not flashy

---

## Designer Brief (One-Liner)

> "Design this like a serious monitoring/observability tool for BEAM agents, not a startup landing page. Code and metrics are the main visuals."

---

## Color Palette

### Base / Neutrals (Dark Mode)

**Backgrounds:**
```css
--bg-body: #050816;          /* Near-black with blue tint (page background) */
--bg-surface: #0B1020;        /* Cards, panels */
--bg-elevated: #111827;       /* Modals, code blocks header, nav */
--code-bg: #020617;           /* Code block backgrounds */
```

**Borders:**
```css
--border-subtle: #1F2937;     /* Subtle dividers */
--border-strong: #374151;     /* Emphasized borders */
--code-border: #111827;       /* Code block borders */
```

**Text:**
```css
--text-primary: #E5ECFF;      /* Main body text */
--text-secondary: #9CA3C7;    /* Supporting text, labels */
--text-muted: #6B7280;        /* Hints, captions, footnotes */
--text-inverted: #020617;     /* Text on bright accents */
--code-text: #E5ECFF;         /* Code default */
--code-comment: #6B7280;      /* Comments */
```

### Brand Accents

**Primary (Magenta/Purple):**
```css
--accent-primary: #C084FC;        /* Main brand color */
--accent-primary-strong: #E879F9; /* Hover, active, graphs */
```

**Secondary (Cyan):**
```css
--accent-secondary: #22D3EE;        /* Supporting color */
--accent-secondary-strong: #38BDF8; /* Hover, charts */
```

### Semantic States

```css
--success: #4ADE80;   /* Success states, checkmarks */
--warning: #FACC15;   /* Warnings, alerts */
--danger: #FB7185;    /* Errors, failures */
--info: #60A5FA;      /* Info states, hints */
```

### Code Syntax Colors

```css
--code-keyword: #C084FC;    /* Magenta - def, use, when */
--code-string: #22D3EE;     /* Cyan - strings */
--code-function: #60A5FA;   /* Blue - function names */
--code-number: #FBBF24;     /* Amber - numbers */
--code-type: #F472B6;       /* Pink - types, modules */
```

### Color Usage Rules

**accent-primary (magenta):**
- Logo mark
- Primary CTAs ("Get Started")
- Selection states
- Focused inputs
- Links on hover
- Active nav items

**accent-secondary (cyan):**
- Metrics lines in charts
- Secondary CTAs ("Read Docs")
- Active code cursors/highlights
- Diagram connections
- Loading states

**Semantic colors:**
- Use ONLY for actual states (success/failure, alerts)
- Not for decoration

**Gradients:**
- Avoid large full-screen gradients
- Use tight, directional gradients (2–4px outline glow around key cards)
- Acceptable: subtle magenta→cyan on hover states for CTAs

---

## Typography

### Font Stacks

**UI / Body (Sans-Serif):**
```css
font-family: 'Inter', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
```

**Alternative:** System UI stack for faster load

**Monospace / Code:**
```css
font-family: 'JetBrains Mono', 'Fira Code', 'IBM Plex Mono', 'Courier New', monospace;
```

**Why these:**
- Inter: Excellent at small sizes, neutral, familiar to developers
- JetBrains Mono: Clear code display, good ligatures, popular in dev tools

### Type Scale (Desktop)

```css
--text-display: 36-42px;     /* Hero headlines */
--text-h1: 28-32px;          /* Section headers */
--text-h2: 22-24px;          /* Subsection headers */
--text-h3: 18-20px;          /* Card titles */
--text-body: 15-16px;        /* Main content */
--text-code: 13-14px;        /* Code blocks */
--text-metric: 24-32px;      /* Metric numbers */
--text-small: 13-14px;       /* Captions, hints */
```

**Line Heights:**
- Headlines: 1.1–1.15
- Body: 1.5–1.6
- Code: 1.4–1.5

**Weights:**
- Display/Headers: 600 (semi-bold)
- Body: 400 (regular)
- Code: 400 (regular) or 500 (medium for emphasis)
- Metrics: 500-600

### Code Presentation Rules

**Block Structure:**
- Max width: 100–110 characters (horizontal scroll if needed)
- Padding: 16–20px inside blocks
- Border: 1px solid `code-border`
- Background: `code-bg`
- Line numbers: left gutter, dimmed to `text-muted`

**Syntax Highlighting:**
- Use defined code syntax colors (keyword, string, function, etc.)
- Avoid overly neon themes—maintain contrast for long reading
- Ensure 4.5:1 contrast ratio minimum for code text

**Inline Code:**
- Backtick style: `text-accent-primary` or `text-accent-secondary`
- Small padding: 2px 4px
- Background: slightly lighter than surface
- No border unless on light backgrounds

### Metric Display

**Number formatting:**
- Use **monospace** for all numbers in metric tiles (alignment)
- Format: `10,000+`, `200MB`, `<1ms`
- Large size (24-32px), semi-bold
- Small label below in `text-secondary` (12-13px)

---

## Logo Design

### Concept Direction

**Primary Metaphor:** Supervision tree / connected processes reflecting BEAM/OTP architecture

**Options:**

1. **Supervision tree inside hexagon**
   - Outer hexagon (nods to Elixir/Hex.pm)
   - Inside: 3-4 nodes in branching pattern (supervisor → agents)
   - Minimal, geometric, 2-3 strokes

2. **Stylized "J" as process path**
   - Angular "J" that looks like branching process diagram
   - Message path visual
   - Simple, iconic

3. **Node cluster**
   - One larger "supervisor" node
   - 3-4 smaller "agent" nodes connected
   - Minimal connecting lines

### Logo Requirements

**Simplicity:**
- Must be legible at 16×16px (favicon)
- Must work at 24×24px (Hex badge)
- No line details thinner than 1.5-2px at 24px size
- No text inside the mark
- Pair with wordmark externally

**Shapes:**
- Geometric: hexagons, circles, short line segments
- Corners: 2-4px radius (serious but not harsh)
- 2-3 stroke weights maximum

**Color Variants:**

**Primary mark (dark backgrounds):**
- White mark (`#E5ECFF`) with subtle magenta→cyan border or internal gradient
- Alternative: Solid `accent-primary`

**Flat mark (any background):**
- Single-color `#E5ECFF` for dark backgrounds
- Single-color `#020617` for light backgrounds

**Hex badge:**
- Works fully filled or outline-only
- Monochrome version for printing

### Wordmark

**Typography:**
- "Jido" in Inter Semi-Bold or equivalent
- Slightly tightened letter-spacing (-0.02em)
- No all-caps, no weird ligatures
- Standard casing: "Jido" or "JIDO" (pick one)

**Lockups:**

**Horizontal (primary):**
```
[Mark] Jido
```
- Mark on left, 12-16px gap, wordmark
- Use in nav, footer, marketing

**Stacked (alternative):**
```
[Mark]
 Jido
```
- Centered alignment
- Use in badges, small spaces

**Mark alone:**
- Favicon
- GitHub org avatar
- Hex.pm avatar
- Social media icons

### What to Avoid

❌ Mascots, faces, robots  
❌ 3D extrusions, gloss, lens flares  
❌ Overly playful (rounded blobs, pastel gradients)  
❌ Abstract "AI swirl" patterns  
❌ Complex details that disappear at small sizes

---

## AI Design Tool Prompts

### Logo Mark Prompts

**Prompt 1 (Supervision tree in hexagon):**
```
Design a minimal flat logo icon for a production-grade Elixir/BEAM agent framework called 'Jido'. Dark background #050816, primary accent magenta #C084FC, secondary accent cyan #22D3EE. The mark should show a supervision tree (one root node, three child nodes) inside a simple hexagon, with clean geometric lines, no text, no mascots, no complex gradients. Must be legible at 16×16 pixels and work as a one-color icon.
```

**Prompt 2 (Stylized "J"):**
```
Create a geometric logo icon that forms a stylized letter 'J' using connected nodes and lines, suggesting a process flow or supervision path. Use simple shapes, 2-3 strokes maximum, no shading, designed for dark UI backgrounds, optimized for GitHub avatar and favicon. Colors: white #E5ECFF with optional magenta #C084FC accent.
```

**Prompt 3 (Node cluster):**
```
Design a minimal icon showing a central supervisor node connected to 3-4 smaller agent nodes, forming a balanced cluster. Geometric shapes only, 2px strokes, dark background #050816, white lines #E5ECFF with magenta #C084FC and cyan #22D3EE accents on connections. Must work at 24×24px and as a Hex package badge.
```

### Hero Section / Landing UI

**Prompt:**
```
Design a dark-mode web landing page hero for a BEAM-native multi-agent framework named 'Jido'. Color palette: background #050816, surfaces #0B1020, text #E5ECFF, accents magenta #C084FC and cyan #22D3EE. 

Layout: Left side shows headline "10,000 supervised agents on a single BEAM node" with two CTAs below. Right side shows a dark code editor panel with Elixir syntax-highlighted code.

Below the hero: horizontal metric strip with large monospace numbers: "10,000+ agents/node", "~200MB RAM @ 5,000 agents", "<1ms intra-node latency"

Style: minimal, dashboard-like, code-first, no marketing illustrations, no large gradients. Clean grid, subtle borders, feels like a developer tool.
```

### Architecture Diagrams

**Prompt 1 (Comparison diagram):**
```
Generate a simple line-based dark-mode diagram comparing two architectures side-by-side. 

Left side: "Thread-Based" with boxes labeled: "Thread Pool" → "Queue" → "Workers", connected with white lines.

Right side: "BEAM Processes" with boxes labeled: "Supervisor" → "Mailbox" → "Processes", with magenta #C084FC highlights on the supervisor and cyan #22D3EE on process connections.

Background: #050816, white text #E5ECFF, 2px strokes, minimal and technical. Should fit in a 800×400px card.
```

**Prompt 2 (Supervision tree):**
```
Create a dark-mode supervision tree diagram for an Elixir application. Root node labeled "Jido.Supervisor", branching to 2-3 agent processes below. Minimalistic, straight lines (no curves), 2px white strokes on #050816 background, nodes are simple rounded rectangles. Accents: magenta #C084FC on supervisor, cyan #22D3EE on agent connections. No shadows, no 3D.
```

### Icon Set

**Prompt:**
```
Design a set of 8-10 minimal line icons for a developer framework documentation. Icons needed: agents, supervision, metrics, telemetry, distributed nodes, actions, signals, benchmarks, examples, community.

Style: 2px strokes, rounded corners (2px), white lines #E5ECFF on dark background with occasional magenta #C084FC or cyan #22D3EE accents. No 3D, no characters, consistent 24×24px size. Should feel like developer tool icons (VS Code, GitHub style).
```

### Component Mockups

**Prompt (Metric card):**
```
Design a dark UI card showing a single metric. Background #0B1020, border #1F2937, 16px padding. Large monospace number "10,000+" in #E5ECFF (32px), small label below "agents per node" in #9CA3C7 (13px), tiny footnote "measured on 2-core, 4GB VM" in #6B7280 (12px). Clean, minimal, dashboard-style.
```

**Prompt (Code block component):**
```
Design a dark code editor panel for documentation. Background #020617, border #111827, header bar with filename "weather_agent.ex" in #9CA3C7 and copy button. Code area with Elixir syntax highlighting: keywords in magenta #C084FC, strings in cyan #22D3EE, functions in blue #60A5FA, line numbers in #6B7280 on left. Monospace font, 14px, clean and readable.
```

---

## Logo Specifications

### Logo Concept: Supervision Tree in Hexagon

**Design:**
- Hexagon outline (2px stroke, `#E5ECFF`)
- Inside: simplified supervision tree
  - One root node (small circle or square, 4px)
  - Three child nodes (3px)
  - Connecting lines (1.5px)
- Optional: subtle magenta→cyan gradient on tree connections
- Total size: fits cleanly in 32×32px grid

**Variants:**

**1. Primary (Full Color):**
- White hexagon outline
- Tree in magenta→cyan gradient
- Use on dark backgrounds

**2. Monochrome (Light):**
- All elements in `#E5ECFF`
- Use on dark backgrounds
- For GitHub dark mode

**3. Monochrome (Dark):**
- All elements in `#020617`
- Use on light backgrounds
- For documentation, print

**4. Hex Badge:**
- Simplified, higher contrast
- Works at 20×20px

### Wordmark

**Typography:**
- Font: Inter Semi-Bold (600 weight)
- Text: "Jido" (sentence case preferred) or "JIDO" (all caps as alternative)
- Letter-spacing: -0.02em
- Color: `text-primary` (#E5ECFF) on dark

**Full Lockup:**
```
[Hexagon Mark]  Jido
    (12-16px gap)
```

**Usage:**
- Horizontal lockup in nav, footer, marketing
- Mark alone for icons, avatars, favicons
- Never scale mark and wordmark disproportionately

### Minimum Sizes

- **Favicon:** 16×16px (mark only, no wordmark)
- **Hex badge:** 24×24px (mark only)
- **GitHub avatar:** 32×32px (mark only)
- **Nav logo:** 40px height (mark + wordmark)
- **Social share:** 1200×630px (mark + wordmark + tagline)

### Clear Space

- Maintain clear space around logo = height of the hexagon
- No other elements within this boundary

### Incorrect Usage

❌ Stretching or distorting proportions  
❌ Rotating the mark  
❌ Changing colors outside defined variants  
❌ Adding effects (drop shadows, glows, gradients not in spec)  
❌ Placing on busy backgrounds without clear space

---

## UI/UX Patterns

### Pattern 1: Dual-View Explanations

**For serving both personas:**

```
┌─────────────────────────────────────┐
│ [Tab: Elixir/OTP] [Tab: Threads/Queues] │
├─────────────────────────────────────┤
│                                     │
│  [Diagram for selected view]        │
│  [Code snippet for selected view]   │
│                                     │
└─────────────────────────────────────┘
```

**Elixir/OTP tab:**
- Supervision tree diagrams
- Direct Jido code
- OTP terminology

**Threads/Queues tab:**
- Comparison diagrams
- Side-by-side with BEAM equivalent
- Terms they know (worker pool, queue, retry)

### Pattern 2: Split Code + Diagram Layout

**Desktop layout:**
```
┌──────────────┬──────────────┐
│   Diagram    │     Code     │
│   (40%)      │     (60%)    │
│              │              │
│  Supervision │  defmodule   │
│  Tree        │  MyAgent do  │
│              │    ...       │
└──────────────┴──────────────┘
```

**Mobile:** Stack vertically (diagram above, code below)

### Pattern 3: Metric Strips

**Horizontal strip below hero or section:**
```
┌────────────┬────────────┬────────────┬────────────┐
│ 10,000+    │ ~200MB     │ <1ms       │ Zero       │
│ agents/    │ RAM @      │ intra-node │ external   │
│ node       │ 5k agents  │ latency    │ queue      │
└────────────┴────────────┴────────────┴────────────┘
```

**Styling:**
- Large monospace numbers (24-32px)
- Small labels below (12-13px, `text-secondary`)
- Optional small hint text (10-11px, `text-muted`)
- Subtle border between items
- Background: `bg-surface` or `bg-elevated`

### Pattern 4: Production Scenario Cards

**Structure:**
```
┌─────────────────────────────────────┐
│ 💥 When an agent crashes            │
├─────────────────────────────────────┤
│                                     │
│ [Small diagram: agent → crash →    │
│  supervisor → restart]              │
│                                     │
│ [Code snippet showing supervisor]   │
│                                     │
│ ✓ Restart in <50ms                 │
│ ✓ Other agents unaffected          │
└─────────────────────────────────────┘
```

**Icons:** Use sparingly, simple line icons only

### Pattern 5: Example Cards

**Structure:**
```
┌─────────────────────────────────────┐
│ Tool-Using Research Agent Swarm     │
├─────────────────────────────────────┤
│ Multi-agent research coordination   │
│                                     │
│ 📊 1,000 agents • 150ms avg        │
│    $0.05/query • 2-core node        │
│                                     │
│ [Livebook] [GitHub] [YouTube]       │
└─────────────────────────────────────┘
```

**Styling:**
- Card background: `bg-surface`
- Border: `border-subtle`
- Hover: lift 2px, `border-strong`, subtle glow
- Metrics use monospace, inline
- Links as small pills/tags

### Pattern 6: Documentation-Style Navigation

**Left sidebar (≥1024px):**
- Fixed position
- Background: `bg-surface`
- Sections collapsible
- Active item: `border-left: 3px solid accent-primary`

**Mobile:**
- Hamburger menu
- Slide-in drawer
- Same styling as desktop

**Breadcrumbs:**
```
Jido / Examples / Multi-Agent Coordination
```
- Small text, separated by `/` or `>`
- Current page in `accent-primary`

---

## Component Specifications

### Buttons

**Primary:**
- Background: `accent-primary`
- Text: `text-inverted`
- Padding: 12px 24px
- Border-radius: 6px
- Hover: `accent-primary-strong` + scale(1.02)
- Icon: optional, left or right, 16px

**Secondary:**
- Background: transparent
- Border: 1px solid `accent-secondary`
- Text: `accent-secondary`
- Hover: background `accent-secondary` + text `text-inverted`

**Ghost:**
- Background: transparent
- Text: `text-secondary`
- Hover: text `text-primary`

### Cards

**Standard card:**
```css
background: var(--bg-surface);
border: 1px solid var(--border-subtle);
border-radius: 8px;
padding: 20px;
```

**Hover state:**
```css
transform: translateY(-2px);
border-color: var(--border-strong);
box-shadow: 0 4px 12px rgba(192, 132, 252, 0.1); /* Subtle magenta glow */
```

### Code Blocks

**Structure:**
```html
<div class="code-block">
  <div class="code-header">
    <span class="filename">weather_agent.ex</span>
    <button class="copy-btn">Copy</button>
  </div>
  <pre><code class="language-elixir">
    [syntax-highlighted code]
  </code></pre>
</div>
```

**Styling:**
```css
.code-block {
  background: var(--code-bg);
  border: 1px solid var(--code-border);
  border-radius: 8px;
  overflow: hidden;
}

.code-header {
  background: var(--bg-elevated);
  padding: 8px 16px;
  border-bottom: 1px solid var(--code-border);
  display: flex;
  justify-content: space-between;
}

pre code {
  font-family: 'JetBrains Mono', monospace;
  font-size: 14px;
  line-height: 1.5;
  padding: 16px;
  display: block;
  overflow-x: auto;
}
```

### Metric Tiles

**Structure:**
```html
<div class="metric-tile">
  <div class="metric-value">10,000+</div>
  <div class="metric-label">agents per node</div>
  <div class="metric-hint">Measured on 2-core, 4GB VM</div>
</div>
```

**Styling:**
```css
.metric-tile {
  text-align: center;
  padding: 16px;
}

.metric-value {
  font-family: 'JetBrains Mono', monospace;
  font-size: 32px;
  font-weight: 600;
  color: var(--text-primary);
  line-height: 1.2;
}

.metric-label {
  font-size: 13px;
  color: var(--text-secondary);
  margin-top: 4px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.metric-hint {
  font-size: 11px;
  color: var(--text-muted);
  margin-top: 4px;
}
```

### Tabs

**Active tab:**
```css
background: var(--bg-surface);
border-bottom: 2px solid var(--accent-primary);
color: var(--text-primary);
```

**Inactive tab:**
```css
background: transparent;
border-bottom: 2px solid transparent;
color: var(--text-secondary);
```

---

## Layout & Grid

### Max Widths

- **Content:** 1080–1200px (centered)
- **Code blocks:** 100-110 characters (~900px at 14px mono)
- **Text blocks:** 65-75 characters (~680px)

### Grid System

**Desktop (≥1024px):**
- 12-column grid
- 24px gutters
- Common splits:
  - 6/6 (code + diagram)
  - 4/8 (sidebar + content)
  - 8/4 (main + aside)

**Tablet (768-1023px):**
- 8-column grid
- 16px gutters
- Most content stacks to single column

**Mobile (<768px):**
- Single column
- 16px side margins
- Cards and code blocks full-width minus margins

### Spacing Scale

```css
--space-xs: 4px;
--space-sm: 8px;
--space-md: 16px;
--space-lg: 24px;
--space-xl: 32px;
--space-2xl: 48px;
--space-3xl: 64px;
```

Use consistently throughout for margins, padding, gaps.

---

## Page-Specific Guidelines

### Home Page

**Hero:**
- 2-column layout at ≥1024px
- Left: Headline + subheadline + 2 CTAs
- Right: Code block (visible without scrolling)
- Below: Metric strip (full width)

**Below fold sections:**
- Alternate layout: text-left/code-right, then code-left/text-right
- Each section ≤ viewport height
- Clear visual breaks between sections

**Footer:**
- Single row with links, badges, social icons
- Background: `bg-surface`
- Subtle top border

### Examples Page

**Layout:**
- Grid of example cards (2-3 columns on desktop)
- Filter tabs at top: All | Beginner | Intermediate | Advanced
- Each card shows: title, scenario, metrics, links

**Hover state:**
- Lift card 2px
- Magenta glow
- Show "View Example →" overlay or button

### Benchmarks Page

**Layout:**
- Hero with summary metrics
- Sections: Single-node | Multi-node | Failure experiments
- Tables with alternating row backgrounds
- Embedded charts (line/bar, dark theme)
- "How to reproduce" section with code

**Charts:**
- Dark theme
- Magenta for Jido metrics
- Cyan for comparisons
- Grid lines: `border-subtle`
- Labels: `text-secondary`

### Ecosystem Page

**Layout:**
- Large dependency graph at top (SVG or Mermaid)
- Package cards below in layers (foundation → core → AI → app)
- Each card links to `/packages/:name`

**Package cards:**
- Icon/logo placeholder
- Package name
- One-line description
- Links: Hex | HexDocs | GitHub
- Dependency note: "Used by: X, Y, Z"

---

## Motion & Interaction

### Transitions

**Standard durations:**
- Micro (hover, focus): 150ms
- Standard (tab switch, card expand): 250ms
- Complex (page transitions): 350ms

**Easing:**
- Default: `cubic-bezier(0.4, 0.0, 0.2, 1)` (ease-out)
- Bounce: None (keep motion flat and professional)

### Hover States

**Links:**
- Color shift to `accent-primary-strong`
- Underline appears (1px)
- Transition: 150ms

**Cards:**
- Transform: `translateY(-2px)`
- Border-color: `border-strong`
- Box-shadow: `0 4px 12px rgba(192, 132, 252, 0.15)`
- Transition: 250ms

**Buttons:**
- Primary: background darkens slightly, scale(1.02)
- Secondary: background fills with accent
- Transition: 150ms

### LiveView-Specific

**Loading states:**
- Skeleton screens in cards: shimmer effect with `bg-surface` → `bg-elevated`
- Inline spinners: small rotating circle in `accent-secondary`

**Real-time updates:**
- Metrics: fade in new value (250ms)
- Charts: animate new data points smoothly
- No jarring pops or flashes

**Page transitions:**
- Fade between pages (if using LiveView navigation)
- Keep header/nav persistent

---

## Accessibility

### Contrast Requirements

**WCAG AA minimum (4.5:1 for text):**
- `text-primary` on `bg-body`: ✅ Passes
- `text-secondary` on `bg-body`: ✅ Check (should pass)
- `accent-primary` on `bg-body`: ⚠️ Check contrast, may need adjustment for small text
- `accent-secondary` on `bg-body`: ✅ Should pass

**Action:** Verify all color combinations with contrast checker

### Focus States

**Keyboard navigation:**
```css
:focus-visible {
  outline: 2px solid var(--accent-secondary);
  outline-offset: 2px;
  border-radius: 4px;
}
```

**Never remove focus indicators**

### Semantic HTML

- Use proper heading hierarchy (h1 → h2 → h3)
- `<nav>` for navigation
- `<article>` for blog posts and examples
- `<section>` with `aria-label` for major sections
- `<code>` for inline code, `<pre><code>` for blocks

### Screen Readers

- All icon buttons need `aria-label`
- Diagrams need `alt` text or `aria-describedby`
- Metric numbers: consider `aria-label` with full description

---

## Design System for Phoenix/LiveView

### Token Structure

**CSS Variables (in `app.css`):**

```css
:root {
  /* Backgrounds */
  --bg-body: #050816;
  --bg-surface: #0B1020;
  --bg-elevated: #111827;
  --code-bg: #020617;

  /* Borders */
  --border-subtle: #1F2937;
  --border-strong: #374151;
  --code-border: #111827;

  /* Text */
  --text-primary: #E5ECFF;
  --text-secondary: #9CA3C7;
  --text-muted: #6B7280;
  --text-inverted: #020617;

  /* Accents */
  --accent-primary: #C084FC;
  --accent-primary-strong: #E879F9;
  --accent-secondary: #22D3EE;
  --accent-secondary-strong: #38BDF8;

  /* States */
  --success: #4ADE80;
  --warning: #FACC15;
  --danger: #FB7185;
  --info: #60A5FA;

  /* Spacing */
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 16px;
  --space-lg: 24px;
  --space-xl: 32px;
  --space-2xl: 48px;
  --space-3xl: 64px;

  /* Typography */
  --font-sans: 'Inter', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', 'Courier New', monospace;
}
```

### Core Components (Phoenix)

**In `lib/jido_web/components/core_components.ex` or similar:**

**1. Button component:**
```elixir
attr :variant, :atom, default: :primary, values: [:primary, :secondary, :ghost]
attr :size, :atom, default: :md, values: [:sm, :md, :lg]
slot :inner_block, required: true

def button(assigns) do
  ~H"""
  <button class={["btn", "btn-#{@variant}", "btn-#{@size}"]}>
    <%= render_slot(@inner_block) %>
  </button>
  """
end
```

**2. Card component:**
```elixir
attr :variant, :atom, default: :surface, values: [:surface, :elevated, :code]
attr :class, :string, default: ""
slot :inner_block, required: true

def card(assigns) do
  ~H"""
  <div class={["card", "card-#{@variant}", @class]}>
    <%= render_slot(@inner_block) %>
  </div>
  """
end
```

**3. Code block component:**
```elixir
attr :language, :string, default: "elixir"
attr :filename, :string, default: nil
attr :show_copy, :boolean, default: true
slot :inner_block, required: true

def code_block(assigns) do
  ~H"""
  <div class="code-block">
    <div :if={@filename} class="code-header">
      <span class="filename"><%= @filename %></span>
      <button :if={@show_copy} class="copy-btn">Copy</button>
    </div>
    <pre><code class={"language-#{@language}"}>
<%= render_slot(@inner_block) %>
    </code></pre>
  </div>
  """
end
```

**4. Metric tile component:**
```elixir
attr :value, :string, required: true
attr :label, :string, required: true
attr :hint, :string, default: nil

def metric(assigns) do
  ~H"""
  <div class="metric-tile">
    <div class="metric-value"><%= @value %></div>
    <div class="metric-label"><%= @label %></div>
    <div :if={@hint} class="metric-hint"><%= @hint %></div>
  </div>
  """
end
```

**5. Tab component:**
```elixir
attr :tabs, :list, required: true
attr :active, :string, required: true

def tabs(assigns) do
  ~H"""
  <div class="tabs">
    <%= for tab <- @tabs do %>
      <button class={["tab", if(@active == tab, do: "active")]}>
        <%= tab %>
      </button>
    <% end %>
  </div>
  """
end
```

### Tailwind Config (if using Tailwind)

```javascript
module.exports = {
  theme: {
    extend: {
      colors: {
        'jido-bg-body': '#050816',
        'jido-bg-surface': '#0B1020',
        'jido-bg-elevated': '#111827',
        'jido-accent-primary': '#C084FC',
        'jido-accent-secondary': '#22D3EE',
        // ... etc
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Courier New', 'monospace'],
      },
    },
  },
}
```

---

## Brand Voice Alignment

### Visual → Voice Mapping

| Brand Voice Trait | Visual Expression |
|------------------|-------------------|
| **Production-hardened pragmatist** | Dark dashboard aesthetic, metric tiles, system monitors |
| **Code-first teacher** | Code blocks above fold, syntax highlighting, line numbers |
| **Evidence-driven skeptic** | Charts, tables, annotated numbers, environment specs |
| **Built for builders** | Minimal chrome, fast load, clear navigation, no marketing fluff |
| **Elixir insider** | Hex colors, supervision tree diagrams, OTP terminology visible |

### Design Checklist (Per Page)

- [ ] Real code visible in first screen
- [ ] At least one metric with context
- [ ] Failure scenario addressed visually
- [ ] No hype language in UI text
- [ ] Links to proof (example, benchmark, docs)
- [ ] Works for both personas (tabs or dual content)

---

## Mockup Feedback

### Current Lovable Mockup Analysis

**What's Working:**
- ✅ Dark theme with code editor aesthetic
- ✅ Magenta/cyan accent combination
- ✅ Code block above fold
- ✅ Clean, minimal navigation
- ✅ "Built for Production, Not Just Prototypes" badge

**What to Refine:**

1. **Hero headline:**
   - Current: "The Elixir Autonomous Agent Framework"
   - Suggested: Lead with constraint first
   - Example: "10,000 Supervised Agents on a Single BEAM Node" (h1)
   - Subheadline: "Production-ready multi-agent framework on Elixir/BEAM" (h2)

2. **Gradient text:**
   - "Autonomous Agent" in gradient is nice, but ensure readability
   - Consider using solid `accent-primary` for "Autonomous" and solid `accent-secondary` for "Agent"
   - Or keep gradient but increase contrast

3. **CTA buttons:**
   - "Get Started" is good (primary)
   - "Read the Cookbook" → change to "Read Examples" or "View Benchmarks" (more concrete)

4. **Add metric strip:**
   - Immediately below code block
   - 3-4 metrics: agents/node, RAM, latency, zero external queue

5. **Code block:**
   - Good placement and size
   - Ensure syntax highlighting uses the defined palette
   - Add filename header: "weather_agent.ex"
   - Add copy button

6. **Navigation:**
   - "Cookbook" → "Examples"
   - "Catalog" → "Ecosystem" or "Packages"
   - Add "Benchmarks" to nav

### Recommendations for Next Iteration

**Hero section:**
```
┌────────────────────────────────────────────────────────┐
│ [Logo] Agent Jido           [Nav Links]   [Get Started]│
├────────────────────────────────────────────────────────┤
│                                                         │
│  10,000 Supervised Agents                [Code Block]  │
│  on a Single BEAM Node                   weather_      │
│                                          agent.ex      │
│  Built on OTP supervision and            [Elixir code] │
│  isolated processes, not external        [visible]     │
│  queues and YAML orchestration.          [with syntax] │
│                                          [highlighting]│
│  [Get Started →] [View Benchmarks]                     │
│                                                         │
│  ┌──────────┬──────────┬──────────┬──────────┐        │
│  │ 10,000+  │ ~200MB   │ <1ms     │ Zero     │        │
│  │ agents/  │ RAM @    │ latency  │ external │        │
│  │ node     │ 5k       │          │ queue    │        │
│  └──────────┴──────────┴──────────┴──────────┘        │
└────────────────────────────────────────────────────────┘
```

---

## Implementation Notes

### Phoenix/LiveView

**Asset pipeline:**
- Use `esbuild` for JS (Tailwind if chosen)
- Serve Inter and JetBrains Mono from Google Fonts or self-host
- Optimize SVG diagrams (inline critical, lazy-load decorative)

**Syntax highlighting:**
- Server-side: Use `Makeup` (Elixir syntax highlighter)
- Client-side: Highlight.js or Prism.js with custom dark theme
- Cache highlighted blocks in ETS if dynamic

**Performance:**
- Target <2s load time for Home
- Lazy-load Elixir Mentor video embeds
- Inline critical CSS
- Use Phoenix's built-in asset fingerprinting

### Responsive Breakpoints

```css
/* Mobile first */
@media (min-width: 640px)  { /* sm */ }
@media (min-width: 768px)  { /* md */ }
@media (min-width: 1024px) { /* lg - desktop */ }
@media (min-width: 1280px) { /* xl */ }
```

**Key breakpoints:**
- 1024px: Left sidebar appears, 2-column layouts activate
- 768px: Example cards go from 1 to 2 columns
- 640px: Metric strips stack vertically

---

## Assets Checklist

### Logos (Generate/Commission)

- [ ] Primary mark (SVG, multiple color variants)
- [ ] Horizontal lockup (mark + wordmark)
- [ ] Favicon (16×16, 32×32, 48×48)
- [ ] GitHub org avatar (200×200)
- [ ] Hex.pm avatar (200×200)
- [ ] Social share image template (1200×630)

### Icons

- [ ] Navigation icons (8-10 minimal line icons)
- [ ] State icons (success, warning, error, info)
- [ ] External link icons (GitHub, Hex, YouTube, etc.)

### Diagrams (Templates)

- [ ] Supervision tree diagram (SVG template)
- [ ] Threads vs Processes comparison (SVG)
- [ ] Multi-node cluster topology (SVG)
- [ ] Package dependency graph (Mermaid or SVG)

### Graphics

- [ ] Metric tile backgrounds/frames
- [ ] Code block frame/chrome
- [ ] Card hover effects (CSS, no images needed)

---

## Design Validation Checklist

Before launching any major design update:

### Brand Alignment
- [ ] Feels like a production tool, not a marketing site
- [ ] Code and metrics are prominent
- [ ] Accents used sparingly and purposefully
- [ ] No hype language in UI text

### Technical Accuracy
- [ ] Code examples use correct syntax
- [ ] Metrics have environment context
- [ ] Diagrams use accurate terminology
- [ ] Links to examples and docs work

### Accessibility
- [ ] Color contrast passes WCAG AA
- [ ] Focus states visible and clear
- [ ] Semantic HTML structure
- [ ] Works with keyboard navigation

### Performance
- [ ] Load time <2s on 3G
- [ ] Code blocks render without layout shift
- [ ] Images/videos lazy-load
- [ ] Works without JavaScript (progressive enhancement)

### Multi-Persona
- [ ] BEAM natives find it familiar (OTP patterns)
- [ ] Migrators find mental model clear (comparisons)
- [ ] Both can navigate to their path quickly

---

## Production Design Workflow

### Phase 1: Logo & Core Tokens
1. [ ] Generate logo variations using AI prompts above
2. [ ] Test logo at all required sizes
3. [ ] Select final logo and create SVG variants
4. [ ] Define CSS variables in Phoenix app
5. [ ] Set up base typography

### Phase 2: Component Library
1. [ ] Build core components (button, card, code, metric)
2. [ ] Test components in isolation
3. [ ] Document component API in Storybook or similar
4. [ ] Verify accessibility

### Phase 3: Page Templates
1. [ ] Build Home page layout
2. [ ] Build Examples grid
3. [ ] Build Benchmarks layout
4. [ ] Build Getting Started with sidebar nav
5. [ ] Test responsive behavior

### Phase 4: Content Integration
1. [ ] Integrate Workbench examples
2. [ ] Add benchmark charts
3. [ ] Embed Elixir Mentor videos
4. [ ] Wire up LiveView interactivity

### Phase 5: Polish & Performance
1. [ ] Optimize load time
2. [ ] Test across devices/browsers
3. [ ] Verify analytics tracking (Plausible)
4. [ ] Final accessibility audit

---

## AI Tool Recommendations

### Logo Generation
- **Midjourney:** Good for exploration, multiple variations
- **DALL·E 3:** Clean, geometric results
- **Figma AI:** If you want to iterate in Figma
- **Recraft.ai:** Vector-first, good for icons

### UI Mockups
- **v0.dev:** Generates React/Tailwind, adaptable to Phoenix
- **Galileo AI:** Good for developer tool UIs
- **Uizard:** Fast iteration
- **Claude with artifacts:** Can generate HTML/CSS directly

### Diagrams
- **Excalidraw:** Hand-drawn style, but can be minimalist
- **Mermaid:** Code-to-diagram, integrates with LiveView
- **draw.io:** Full control, export SVG
- **Whimsical:** Clean, simple diagrams

### Icon Sets
- **Heroicons:** Minimal line icons, MIT licensed
- **Lucide:** Similar style, extensive library
- **Phosphor:** Developer-friendly icons
- **Custom:** Use AI prompts above to generate specific set

---

## Next Steps

### Immediate (This Week)
1. [ ] Generate 3-5 logo variations using prompts above
2. [ ] Test logos at favicon size
3. [ ] Select final logo direction
4. [ ] Set up CSS variables in Phoenix app

### Week 2
1. [ ] Build core component library (button, card, code, metric)
2. [ ] Create Home page hero mockup
3. [ ] Test on mobile and desktop

### Week 3
1. [ ] Implement full Home page
2. [ ] Add syntax highlighting for code blocks
3. [ ] Integrate first Elixir Mentor video embed
4. [ ] Set up Plausible custom events

### Week 4
1. [ ] Complete Examples and Benchmarks pages
2. [ ] Responsive testing and refinement
3. [ ] Accessibility audit
4. [ ] Launch updated design

---

## Resources

### Inspiration Sites (Developer Tools)

- **Grafana** – Dashboard aesthetics, dark theme, metrics
- **Linear** – Clean, minimal, fast
- **Vercel** – Code-first, excellent typography
- **Supabase** – Developer-focused, good balance
- **Fly.io** – Technical, approachable, Elixir-friendly

### Design Systems to Reference

- **Tailwind UI** – Component patterns
- **Radix UI** – Accessible primitives
- **shadcn/ui** – Dark theme inspiration
- **GitHub Primer** – Developer tool patterns

### Contrast Checkers

- **WebAIM Contrast Checker:** https://webaim.org/resources/contrastchecker/
- **Coolors Contrast Checker:** https://coolors.co/contrast-checker

### Syntax Highlighting Themes

- **One Dark Pro** (VS Code theme) – Good reference
- **Tokyo Night** – Popular dark theme
- **Dracula** – High contrast, developer favorite

---

**Visual identity should feel like: A production monitoring tool for the BEAM, not a SaaS marketing site.**
