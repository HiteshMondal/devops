# Git & GitHub — Fundamentals Interview Guide
> *Beginner-level reference: core concepts, commands, and the most commonly asked interview questions.*

---

## Table of Contents

1. [Git Basics & Concepts](#1-git-basics--concepts)
2. [Core Git Commands](#2-core-git-commands)
3. [Branching & Merging](#3-branching--merging)
4. [Undoing Changes](#4-undoing-changes)
5. [Remote Repositories & GitHub](#5-remote-repositories--github)
6. [GitHub-Specific Concepts](#6-github-specific-concepts)
7. [.gitignore & Configuration](#7-gitignore--configuration)
8. [Common Beginner Interview Questions](#8-common-beginner-interview-questions)
9. [Quick Command Cheat Sheet](#9-quick-command-cheat-sheet)

---

## 1. Git Basics & Concepts

**Q1: What is Git, and why is it used?**

Git is a **distributed version control system (VCS)** — it tracks changes to files over time so multiple people can collaborate on the same codebase without overwriting each other's work. Unlike older centralized VCS tools (e.g., SVN), every developer has a **full copy of the repository history** on their own machine, so most operations (commit, view history, create branches) work offline and don't need a network round-trip to a central server.

**Q2: What is the difference between Git and GitHub?**

**Git** is the version control tool itself — it runs locally on your machine and manages history, branches, and commits. **GitHub** is a **cloud-hosting platform** built around Git — it stores remote copies of Git repositories and adds collaboration features on top: Pull Requests, Issues, code review, Actions (CI/CD), project boards, and access control. Git can be used entirely without GitHub (e.g., with GitLab, Bitbucket, or just a private server); GitHub is one of several companies that host Git repositories.

**Q3: What is a repository ("repo")?**

A repository is a folder that Git is tracking — it contains your project files plus a hidden `.git` directory holding the entire history, branches, commits, and configuration. A repo can be **local** (on your machine) or **remote** (hosted on GitHub/GitLab/etc.).

**Q4: What are the three main areas in Git's workflow?**

1. **Working Directory** — the actual files you're editing on disk.
2. **Staging Area (Index)** — a "waiting room" where you mark exactly which changes you want included in the next commit (`git add`).
3. **Repository (`.git` folder / commit history)** — where committed snapshots are permanently stored (`git commit`).

This three-stage model is why `git add` and `git commit` are separate steps — it lets you build a commit from only *some* of your changed files, not everything at once.

**Q5: What is a commit?**

A commit is a **permanent snapshot** of the staged changes at a point in time, identified by a unique SHA-1 hash (e.g., `a3f5c9d`). Each commit stores the snapshot itself, a pointer to its parent commit(s), the author, timestamp, and a commit message — forming a chain that represents the project's full history.

---

## 2. Core Git Commands

**Q6: What does `git init` do?**

Initializes a new, empty Git repository in the current folder — creates the hidden `.git` directory that will store all future history. Used once, when starting to track a brand-new project.

**Q7: What is the difference between `git clone` and `git init`?**

`git init` starts a **new** repository from scratch (empty history). `git clone <url>` **copies an existing remote repository** (all its history, branches, and files) down to your local machine in one step — this is how you start working on a project that already exists on GitHub.

**Q8: What does `git status` show?**

Displays the current state of the working directory and staging area: which files are modified, staged, or untracked, and which branch you're currently on. It's the command developers run most often to orient themselves before committing.

**Q9: What's the difference between `git add .` and `git add <filename>`?**

`git add <filename>` stages one specific file. `git add .` stages **all** modified and new files in the current directory (and subdirectories) at once. Staging selectively is useful when you've changed multiple unrelated things but want to split them into separate, focused commits.

**Q10: What does `git commit -m "message"` do, and why does the message matter?**

Creates a new commit from everything currently staged, with `"message"` as the commit description. Good commit messages (short summary line, imperative mood — "Fix login bug" not "Fixed" or "Fixes") matter because they're the primary way teams understand *why* a change was made when reviewing history later, months after the fact.

**Q11: What is `git log` used for?**

Shows the commit history for the current branch — commit hashes, authors, dates, and messages, most recent first. Common flags: `git log --oneline` (compact one-line-per-commit view), `git log --graph` (visualizes branch/merge structure).

**Q12: What's the difference between `git diff` and `git diff --staged`?**

`git diff` shows changes in the working directory that are **not yet staged**. `git diff --staged` (or `--cached`) shows changes that **are staged** but not yet committed. This lets you review exactly what will go into your next commit before running `git commit`.

---

## 3. Branching & Merging

**Q13: What is a branch, and why use one?**

A branch is an independent, movable pointer to a line of commits — it lets you work on a new feature or fix in isolation without touching the stable `main`/`master` branch. Multiple developers can work on different branches simultaneously, then bring their work together later without disrupting each other.

**Q14: What are the basic branch commands?**

- `git branch` — list local branches.
- `git branch <name>` — create a new branch.
- `git checkout <name>` / `git switch <name>` — switch to a branch.
- `git checkout -b <name>` / `git switch -c <name>` — create and switch in one step.
- `git branch -d <name>` — delete a branch (safe — only if merged).

**Q15: What is `git merge`, and what is a "fast-forward" merge?**

`git merge <branch>` combines the history of another branch into your current branch. A **fast-forward merge** happens when the current branch has no new commits since the other branch diverged — Git simply moves the pointer forward, with no new merge commit needed. If both branches have diverged (new commits on each side), Git creates a **merge commit** with two parents to combine them.

**Q16: What is a merge conflict, and how do you resolve one?**

A merge conflict occurs when Git can't automatically reconcile changes because **the same lines in the same file** were modified differently on both branches. Git marks the conflicting sections directly in the file with `<<<<<<<`, `=======`, and `>>>>>>>` markers. To resolve: open the file, manually edit it to keep the correct/combined content, remove the conflict markers, then `git add <file>` and `git commit` (or `git merge --continue`) to finalize.

**Q17: What is `git rebase`, and how is it different from `git merge`?**

`git merge` combines two branches' histories by creating a new merge commit that preserves both branches' original commit history exactly as it happened. `git rebase` instead **replays** your branch's commits one by one on top of the target branch, producing a **linear, cleaner history** with no merge commit — but it rewrites commit hashes, so it should be avoided on commits that have already been pushed and shared with others (rewriting shared history causes confusion for collaborators).

**Q18: What is `git stash` used for?**

Temporarily saves uncommitted changes (both staged and unstaged) without committing them, and reverts the working directory to a clean state — useful when you need to quickly switch branches (e.g., to fix an urgent bug) without losing in-progress work. `git stash pop` reapplies the most recently stashed changes.

---

## 4. Undoing Changes

**Q19: What's the difference between `git reset` and `git revert`?**

`git revert <commit>` creates a **new commit** that undoes the changes from a previous commit — safe for shared/pushed history since nothing is deleted, only added. `git reset` **moves the branch pointer** backward (and optionally discards commits/changes entirely, depending on `--soft`/`--mixed`/`--hard`) — it rewrites history, so it's only safe for commits that haven't been pushed/shared yet.

**Q20: What are the three modes of `git reset`?**

- `--soft` — moves the branch pointer only; changes stay staged.
- `--mixed` (default) — moves the pointer and unstages changes, but keeps them in the working directory.
- `--hard` — moves the pointer and **permanently discards** all changes in the working directory and staging area — this is destructive and cannot be undone (except via `git reflog` in some cases).

**Q21: What is `git checkout -- <file>` (or `git restore <file>`) used for?**

Discards **uncommitted** changes to a specific file, reverting it back to the last committed version. Useful for quickly throwing away an experimental edit you don't want to keep.

---

## 5. Remote Repositories & GitHub

**Q22: What is a "remote" in Git?**

A remote is a named reference to a version of your repository hosted elsewhere (typically on GitHub/GitLab). The default remote name when you clone a repo is `origin`. You can have multiple remotes (e.g., `origin` for your fork, `upstream` for the original project).

**Q23: What's the difference between `git fetch` and `git pull`?**

`git fetch` downloads new commits/branches from the remote **without merging them** into your current branch — it just updates your local knowledge of the remote's state. `git pull` does a `fetch` **followed immediately by a merge** (or rebase, if configured) into your current branch. `fetch` is the safer choice when you want to review incoming changes before integrating them.

**Q24: What does `git push` do, and what is a common error beginners hit?**

`git push` uploads your local commits to the remote repository. A common beginner error is `rejected — non-fast-forward`, which happens when the remote has commits you don't have locally yet (e.g., a teammate pushed first) — the fix is to `git pull` (integrate their changes) before pushing again, rather than force-pushing over their work.

**Q25: What does `git push --force` do, and why is it risky?**

Overwrites the remote branch's history with your local branch's history, even if they've diverged — **permanently discarding** any commits on the remote that aren't in your local branch. Risky on shared branches (like `main`) because it can silently erase a teammate's work; `--force-with-lease` is a safer alternative that fails if someone else has pushed since you last fetched.

---

## 6. GitHub-Specific Concepts

**Q26: What is a Pull Request (PR)?**

A Pull Request is GitHub's mechanism for proposing that changes from one branch (often on a fork or feature branch) be merged into another (usually `main`). It provides a dedicated space for code review — teammates can comment on specific lines, request changes, run automated CI checks, and approve — before the merge actually happens. (On GitLab, the equivalent is called a **Merge Request**.)

**Q27: What is the difference between "Fork" and "Clone"?**

**Forking** creates your own **copy of someone else's repository under your own GitHub account** — used when you don't have write access to the original repo (e.g., contributing to open source) and need your own remote copy to work from. **Cloning** downloads a copy of a repository (yours or anyone's) to your **local machine**. A typical open-source contribution flow is: fork (on GitHub) → clone (to local machine) → branch → commit → push to your fork → open a Pull Request back to the original repo.

**Q28: What are GitHub Issues used for?**

Issues are GitHub's built-in tracker for bugs, feature requests, and tasks — each Issue can have labels (`bug`, `enhancement`), assignees, milestones, and a discussion thread. They're often linked to Pull Requests (e.g., a commit message containing `Fixes #42` automatically closes Issue #42 when merged).

**Q29: What is a GitHub Actions workflow, at a beginner level?**

A YAML file (`.github/workflows/*.yml`) that defines automated tasks triggered by repository events (a push, a Pull Request, a schedule) — most commonly used to automatically run tests, linters, or build/deploy steps whenever code changes, without a human manually running them.

**Q30: What does "protected branch" mean on GitHub?**

A branch (usually `main`) configured with rules that prevent direct pushes — for example, requiring changes to go through a Pull Request, requiring at least one approving review, and requiring CI checks to pass before merging is allowed. This prevents accidental or unreviewed changes from reaching production code.

---

## 7. .gitignore & Configuration

**Q31: What is a `.gitignore` file for?**

Lists file and folder patterns that Git should **never track or stage**, even if they exist in the project folder — e.g., `node_modules/`, `.env`, `*.log`, build output folders. This keeps secrets, dependencies, and generated files out of version control, since they're either sensitive, huge, or trivially regenerable.

**Q32: What's the difference between `git config --global` and without `--global`?**

`git config --global user.name "..."` sets a setting (like your name/email) for **every** repository on your machine, stored in `~/.gitconfig`. Running the same command without `--global` inside a specific repo sets it **only for that one repository**, overriding the global default — useful when using a different email for work vs. personal projects.

**Q33: What is a `README.md`, and why does every repo have one?**

The README is the first file GitHub displays when someone visits a repository — it typically explains what the project does, how to install/run it, and how to contribute. It's markdown-formatted (hence `.md`) so it renders with headings, code blocks, and links directly on GitHub's web interface.

---

## 8. Common Beginner Interview Questions

**Q34: "You accidentally committed a file with a password in it. What do you do?"**

Removing it in a new commit isn't enough — the password still exists in the **commit history** and can be found by anyone with repo access. The correct approach: (1) immediately rotate/invalidate the leaked credential (treat it as compromised regardless of what else you do), (2) then rewrite history to strip it (e.g., using `git filter-repo` or GitHub's secret-scanning removal guidance), and (3) force-push the cleaned history — coordinating with the team since this rewrites shared commits.

**Q35: "Your teammate pushed changes to the same branch you're working on. What happens when you try to push?"**

Git rejects the push (`non-fast-forward` error) because your local branch is missing commits that exist on the remote. You need to integrate their changes first — either `git pull` (merge) or `git pull --rebase` (replay your commits on top) — resolve any conflicts that arise, and then push again.

**Q36: "What's the difference between `main` and a feature branch, and why not just commit directly to `main`?"**

`main` represents the stable, deployable state of the project. Committing directly to it means every half-finished change is immediately visible to the whole team (and potentially deployed). Feature branches isolate work-in-progress so `main` stays clean, and changes only land there after review via a Pull Request — reducing the risk of breaking the shared codebase.

**Q37: "How would you find which commit introduced a bug?"**

`git bisect` performs an automated **binary search** through commit history — you mark a known-good commit and a known-bad commit, and Git checks out commits in between for you to test as good/bad, narrowing down to the exact commit that introduced the issue in `O(log n)` steps rather than checking every commit one by one.

**Q38: "What is `git blame` used for?"**

Shows, line by line, which commit (and author) last modified each line of a file — useful for understanding the context or reasoning behind a specific piece of code by tracing it back to the commit message and author who wrote it.

---

## 9. Quick Command Cheat Sheet

| Command | Purpose |
|---|---|
| `git init` | Start a new local repository |
| `git clone <url>` | Copy a remote repository locally |
| `git status` | Show current changes / staging state |
| `git add <file>` / `git add .` | Stage specific file / all changes |
| `git commit -m "msg"` | Save staged changes as a snapshot |
| `git log --oneline` | View compact commit history |
| `git diff` | Show unstaged changes |
| `git branch` | List branches |
| `git checkout -b <name>` | Create and switch to a new branch |
| `git merge <branch>` | Merge another branch into current one |
| `git rebase <branch>` | Replay current branch's commits onto another |
| `git stash` / `git stash pop` | Temporarily shelve / restore changes |
| `git pull` | Fetch + merge from remote |
| `git fetch` | Download remote changes without merging |
| `git push` | Upload local commits to remote |
| `git push --force-with-lease` | Safer force-push (fails if remote has new commits) |
| `git reset --hard <commit>` | Discard changes back to a commit (destructive) |
| `git revert <commit>` | Safely undo a commit via a new commit |
| `git bisect` | Binary-search commit history for a bug |
| `git blame <file>` | Show who last changed each line |

---

*This document covers Git and GitHub fundamentals for beginner-level interviews — core commands, branching/merging, undoing changes, and GitHub-specific collaboration features (Pull Requests, Issues, Actions, Forks).*
