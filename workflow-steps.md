1. 
    Precondition:
        - Clean Working space
        - No detached head
        - No task already open
        - Branch name not in protectedBranches
    Command:
        `/dc:start-task <description>`
        * If description is empty, stop and explain command (as sdd)
    Steps:
        - Read description
        - Read current commit hash (commit-ref)
        - Ask dev for clarification until description is concrete (one at a time) **
        - Generate spec.md file for dev to review it.
        - agent says “type ‘specification agreed’, then run /dc:plan”, and stop.
    Based on:
        - https://github.com/addyosmani/agent-skills/blob/main/skills/spec-driven-development/SKILL.md Phase 1
        - https://github.com/alfredoperez/sdd/blob/main/skills/specify/SKILL.md steps 1 to 5
        ** interview me skill: https://github.com/addyosmani/agent-skills/blob/main/skills/interview-me/SKILL.md
2. 
    Precondition:
        - spec.md file exists
        - Dev explicitly agrees with spec "specification agreed"
        - spec.md hash has not changed since approval
    Command:
        `/dc:plan`
    Steps:
        - Operate read-only
        - Identify dependency graph
        - Vertical slicing
        - Write tasks
        - Order tasks
        - Generate checkpoints (a checkpoint contains an ID, a task list, acceptance criteria, ...)
        - Generate plan.md
        - Agent says “type ‘Plan agreed’, run /clear, then /dc:implement”, and stop.
    Based on:
        - https://github.com/addyosmani/agent-skills/blob/main/skills/planning-and-task-breakdown/SKILL.md  
3. 
    Precondition:
        - plan.md exists
        - Dev explicitly agrees with plan "Plan agreed"
        - Session is not the one that ran /dc:plan: the user has run /clear since (based on hook)
        - plan.md hash has not changed since approval
    Command:
        `/dc:implement [<checkpoint>]`
    Steps:
        (A implementation block is considered: implement -> test -> verify)
        - Read plan.md
        - Read implementation-notes.md (if existing)
        - Choose the checkpoint: the one provided, or else the first one not yet in implementation-notes.md (plan order).
            * If the provided checkpoint is already in implementation-notes.md, say so and stop.
            * If an earlier checkpoint is not done yet, say which one and stop.
        - Perform the implementation block for that checkpoint only, then stop for the dev to validate. The dev runs /dc:implement again for the next one (no /clear needed between checkpoints).
        - If the agent must deviate from the plan, stops and asks the dev for feedback.
        - Agent NEVER commits
        - Write implementation-notes.md with one entry per checkpoint specifying modifications, lightweight technical decissions (lower risk)
    Based on:
        - https://github.com/addyosmani/agent-skills/blob/main/skills/incremental-implementation/SKILL.md
4. 
    Precondition:
        - implementation-notes.md exists
        - implementation-notes.md contains all checkpoints present in plan.md
    Command:
        `/dc:assessment`
    Steps:
        - Determine source (`git diff commit-ref` and/or implementation-notes.md), where commit-ref is the commit hash recorded by /dc:start-task
            * Also include untracked files (`git ls-files --others --exclude-standard`): the agent never commits, so files it created don't appear in `git diff`
        - Generate N questions relative to diff size
        - Generate expected answers to previous questions before asking any question to the user
        - Ask one question at a time. Retry limit configurable by tech lead.
        - For correct answers, continue. For incorrect rephrase + hint + different related question. For "not sure", agent explains the block and asks related question. 
        - Writes assessment.md file with questions and answers from dev word-by-word (hook) and a overall result passed/total
    Based on:
        - https://github.com/rodbv/socratic-skills/blob/main/skills/quiz-me/SKILL.md
5. 
    Precondition:
        - spec.md exists
        - assessment is finished
    Command:
        `/dc:pr-text`
    Steps:
        - Read spec.md
        - Read plan.md
        - Read implementation-notes.md
        - Read assessment.md
        - Write pr-text.md, a summary (<3000 chars) containing relevant information from each file. Specifying what has been developed (spec.md) how (plan.md + implementation-notes.md) and dev understanding (assessment.md)
    Based on:
        - https://github.com/alfredoperez/sdd/blob/main/skills/implement/SKILL.md steps 7 and 8 (PR body: What and Why from spec.md, Testing from tasks.md, previewed for approval)
        - https://github.com/addyosmani/agent-skills/blob/main/skills/git-workflow-and-versioning/SKILL.md section "Change Summaries" (changes made, things intentionally not touched, potential concerns)