# Architectural Decision Records (ADRs)

This directory contains Architectural Decision Records (ADRs) for JidoCode.

## What is an ADR?

An ADR is a document that captures an important architectural decision made along with its context and consequences. ADRs help us:

- **Remember** why decisions were made
- **Communicate** decisions to team members
- **Onboard** new contributors quickly
- **Revisit** decisions when context changes

## ADR Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0000](0000-template.md) | Template | - | - |
| [0001](0001-tool-security-architecture.md) | Tool Security Architecture | Accepted | 2024-12-28 |

## Creating a New ADR

1. Copy `0000-template.md` to `NNNN-short-title.md` (use next available number)
2. Fill in all sections
3. Set status to "Proposed"
4. Submit for review
5. Update status to "Accepted" when approved

## ADR Lifecycle

```
Proposed → Accepted → [Deprecated | Superseded]
```

- **Proposed**: Under discussion, not yet decided
- **Accepted**: Decision is in effect
- **Deprecated**: No longer applies (context changed)
- **Superseded**: Replaced by a newer ADR

## Guidelines

- Keep ADRs concise but complete
- Focus on the "why" not just the "what"
- Document alternatives even if not chosen
- Link to relevant code and other ADRs
- Update the index when adding new ADRs
