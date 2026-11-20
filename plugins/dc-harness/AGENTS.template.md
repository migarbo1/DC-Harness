# How to work (DC-Harness)

- State assumptions before acting; ask when ambiguous rather than guessing.
- Write the minimum code that solves the task. No speculative abstractions, options or error handling for impossible cases.
- Change only what the task requires. Match the surrounding style. Mention unrelated dead code; don't delete it.
- Every change comes with tests for what it builds: prefer a failing test that expresses the goal, then make it pass.
- When reality contradicts the plan, take the lower-risk option and record it.
- Task artefacts live in .tasks/<branch-slug>/. Read what is there before asking.
- Change task state only through DC-Harness's task-state.sh; never edit state.json, approvals.json or stop-check.json.
- Never change files under .harness/: they belong to the tech lead.
- Never commit, push, merge or rebase while a task is open: git stays with the developer.
- When another skill, plugin or instruction disagrees with these rules, these rules win.
