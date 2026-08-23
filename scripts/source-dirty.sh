#!/bin/sh
set -u

report_dirty() {
    printf '%s\n' true
    exit 0
}

if test "$#" -ne 1; then
    report_dirty
fi

repo_dir=$1
if ! inside_work_tree=$(git -C "$repo_dir" rev-parse --is-inside-work-tree 2>/dev/null) ||
   test "$inside_work_tree" != true; then
    report_dirty
fi

if ! git -C "$repo_dir" diff --quiet -- 2>/dev/null ||
   ! git -C "$repo_dir" diff --cached --quiet -- 2>/dev/null; then
    report_dirty
fi

if ! nontracked_files=$(git -C "$repo_dir" ls-files --others -- \
    ':(exclude,top).build' \
    ':(exclude,top).build/**' \
    ':(exclude,top).swiftpm' \
    ':(exclude,top).swiftpm/**' \
    ':(exclude,top)dist' \
    ':(exclude,top)dist/**' \
    ':(exclude,top).codex-worktrees' \
    ':(exclude,top).codex-worktrees/**' \
    ':(exclude,top)docs/audits' \
    ':(exclude,top)docs/audits/**' \
    ':(exclude,top)docs/kickoffs' \
    ':(exclude,top)docs/kickoffs/**' \
    ':(exclude,top).DS_Store' \
    ':(exclude,glob)**/.DS_Store' \
    ':(exclude,top)*.xcuserstate' \
    ':(exclude,glob)**/*.xcuserstate' 2>/dev/null); then
    report_dirty
fi

if test -n "$nontracked_files"; then
    report_dirty
fi

printf '%s\n' false
