# Ralph Agent Instructions

## Your Task

Split the large package of ExSolana (in projects/ex_solana_v1) into smaller packages, modernized to Agent Jido ecosystem standards - see the `GENERIC_PACKAGE_QA.md` for quality standards. Maintain test coverage and quality. Utilize the foundational packages of `zoi`, `req` and `splode`. Reference other Jido ecosystem package for examples as needed.

See /home/sprite/jido_workspace/notes/solana-split/research.md and /home/sprite/jido_workspace/notes/solana-split/plan.md

1. Read `ralph/prd.json`
2. Read `ralph/progress.txt`
   (check Codebase Patterns first)
3. Check you're on the correct branch
4. Pick highest priority story 
   where `passes: false`
5. Implement that ONE story
6. Run typecheck and tests
7. Update AGENTS.md files with learnings
8. Use Conventional Commits to commit your changes
9. Update prd.json: `passes: true`
10. Append learnings to progress.txt

## Progress Format

APPEND to progress.txt:

## [Date] - [Story ID]
- What was implemented
- Files changed
- **Learnings:**
  - Patterns discovered
  - Gotchas encountered
---

## Codebase Patterns

Add reusable patterns to the TOP 
of progress.txt:

## Codebase Patterns
- Migrations: Use IF NOT EXISTS
- React: useRef<Timeout | null>(null)

## Stop Condition

If ALL stories pass, reply:
<promise>COMPLETE</promise>

Otherwise end normally.
