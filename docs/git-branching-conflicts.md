# Git branching and merge conflict primer

Git branches are movable names that point at commits. A commit records a snapshot
of the project plus a pointer to its parent commit.

When you create a branch, Git creates a new name at the current commit:

```bash
git switch -c feature/readme-update
```

New commits move only the branch you are currently on:

```text
main:              A---B
                       \
feature/readme-update: C---D
```

Merging asks Git to combine the history from another branch into your current
branch:

```bash
git switch main
git merge feature/readme-update
```

If both branches changed different lines, Git usually merges automatically. If
both branches changed the same nearby lines, Git stops and asks you to decide
which final content should win.

## Can git-delta help with merge conflicts?

Yes, but `git-delta` is a viewer, not a resolver.

This repo already configures Git to use delta as the pager, so commands such as
`git diff`, `git show`, and `git add -p` are easier to read. During a conflict,
delta can make the conflicting diff clearer, but you still resolve the conflict
by editing files, choosing one side, or using a merge tool.

Useful conflict review commands:

```bash
git status
git diff --name-only --diff-filter=U
git diff --merge
git diff --merge -- path/to/file
```

Because `core.pager = delta` is configured, those diffs are rendered through
delta automatically.

## Conflict markers

A conflicted file contains markers like this:

```text
<<<<<<< HEAD
content from the branch you had checked out
=======
content from the branch you are merging in
>>>>>>> feature/readme-update
```

Read this as:

| Marker | Meaning |
|---|---|
| `<<<<<<< HEAD` | Start of your current branch's version. |
| `=======` | Separator between the two versions. |
| `>>>>>>> branch-name` | End of the incoming branch's version. |

The final file must remove all markers and keep the correct final content.

For more context in future conflicts, enable the `zdiff3` conflict style:

```bash
git config --global merge.conflictStyle zdiff3
```

That adds a base section showing what both branches started from, which often
makes the intended resolution easier to see.

## Efficient conflict workflow

Start from a clean worktree:

```bash
git status
```

Update the target branch:

```bash
git switch main
git pull
```

Bring the target branch into your feature branch before opening a pull request:

```bash
git switch feature/readme-update
git merge main
```

If conflicts happen:

```bash
git status
git diff --name-only --diff-filter=U
git diff --merge -- path/to/file
```

Then resolve each file:

1. Open the conflicted file.
2. Decide the final content.
3. Remove `<<<<<<<`, `=======`, and `>>>>>>>` markers.
4. Run the relevant test or syntax check.
5. Stage the resolved file with `git add path/to/file`.

Finish the merge:

```bash
git status
git commit
```

If the merge is going badly and you want to return to the pre-merge state:

```bash
git merge --abort
```

## Choosing one side quickly

Sometimes the right answer is simply one side of a conflicted file.

Keep your current branch's version:

```bash
git checkout --ours -- path/to/file
git add path/to/file
```

Keep the incoming branch's version:

```bash
git checkout --theirs -- path/to/file
git add path/to/file
```

Use these only when replacing the whole file is correct. For most source files,
manually editing the final content is safer.

## Reduce future conflicts

Keep branches small and short-lived. Merge or rebase from `main` regularly so
conflicts are handled while the changes are still fresh.

Enable Git's recorded resolution reuse:

```bash
git config --global rerere.enabled true
```

`rerere` remembers how you resolved a conflict and can replay the same
resolution if the same conflict appears again.

Prefer mechanical changes in separate commits. Formatting a file and changing
logic in the same commit makes conflicts harder to review.

Before merging or rebasing, inspect what changed on each side:

```bash
git diff main...HEAD
git log --oneline --graph --decorate --all
```

## Merge vs rebase

Use `merge` when you want a visible record that two lines of work were combined:

```bash
git merge main
```

Use `rebase` on your own local branch when you want to replay your commits on
top of the latest target branch:

```bash
git rebase main
```

Do not rebase shared branches unless the team has agreed to rewrite that branch's
history.

