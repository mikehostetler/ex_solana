0a. Study specs/* to learn about the Docket Hauler application specifications for migration from React-Boilerplate to Vite+React+TypeScript

0b. The legacy source code is in docket-hauler/ and the new target application should be created in new-docket-hauler/

1. Study @fix_plan.md for migration issues and blockers

1. Your task is to port the legacy React-Boilerplate application to a modern Vite+React+TypeScript stack while preserving 100% business functionality. Use parallel subagents to implement different feature slices independently. You may use up to 500 parallel subagents for all operations.

2. After implementing functionality or resolving migration issues, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications. Think hard.

2. When you discover migration, compatibility, or architectural issues, immediately update @fix_plan.md with your findings using a subagent. When the issue is resolved, update @fix_plan.md and remove the item using a subagent.

3. When the tests pass update the @fix_plan.md, then add changed code and @fix_plan.md with "git add -A" via bash then do a "git commit" with a message that describes the changes you made to the code. After the commit do a "git push" to push the changes to the remote repository.

999. Important: When authoring documentation (ie. React component docs or TypeScript interfaces) capture the why tests and the backing implementation is important.

9999. Important: We want single sources of truth, no migrations/adapters. If tests unrelated to your work fail then it's your job to resolve these tests as part of the increment of change.

999999. As soon as there are no build or test errors create a git tag. If there are no git tags start at 0.0.0 and increment patch by 1 for example 0.0.1 if 0.0.0 does not exist.

999999999. You may add extra logging if required to be able to debug the migration issues.


9999999999. ALWAYS KEEP @fix_plan.md up to date with your learnings using a subagent. Especially after wrapping up/finishing your turn.

99999999999. When you learn something new about how to run the legacy or new application make sure you update @AGENT.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.

999999999999. IMPORTANT DO NOT IGNORE: The new application should be implemented in TypeScript with React 18 functional components and hooks. If you find class components in the legacy code, migrate them to functional components.

99999999999999. IMPORTANT when you discover a bug resolve it using subagents even if it is unrelated to the current piece of work after documenting it in @fix_plan.md


9999999999999999. When you start implementing feature slices in the new application, start with the authentication slice so that other features can be properly protected.


99999999999999999. The tests for the new application should be located next to the source code they test. Ensure you document each feature slice with a README.md in the same folder as the source code.


9999999999999999999. Keep AGENT.md up to date with information on how to build both legacy and new applications and your learnings to optimize the development/test loop using a subagent.


99999999999999999999999999. If you find inconsistencies in the specs/* then use the oracle and then update the specs. Specifically around React patterns, TypeScript interfaces, and Firebase integration.

9999999999999999999999999999. DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS. WE WANT FULL IMPLEMENTATIONS WITH COMPLETE BUSINESS LOGIC. DO IT OR I WILL YELL AT YOU


9999999999999999999999999999999. SUPER IMPORTANT DO NOT IGNORE. DO NOT PLACE STATUS REPORT UPDATES INTO @AGENT.md