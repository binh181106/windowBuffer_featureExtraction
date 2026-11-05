#!/usr/bin/env bash
# Dong bo nhanh hien tai voi origin/main. KHONG tu giai quyet conflict.
set -u
cd "$(git rev-parse --show-toplevel)" 2>/dev/null || exit 0

echo "=== [sync] git fetch ==="
git fetch --quiet origin 2>&1 | sed 's/^/    /'

BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE=$(git merge-base HEAD origin/main 2>/dev/null) || exit 0
BEHIND=$(git rev-list --count "$BASE"..origin/main 2>/dev/null || echo 0)
LOCAL=$(git rev-list --count "$BASE"..HEAD 2>/dev/null || echo 0)

echo "=== [sync] branch=$BRANCH  ahead=$LOCAL  behind=$BEHIND ==="

if [ "$BEHIND" -gt 0 ]; then
  if [ -z "$(git status --porcelain)" ]; then
    echo "[sync] clean tree -> rebase onto origin/main"
    git rebase origin/main 2>&1 | sed 's/^/    /'
  else
    echo "[sync] WARNING: co thay doi chua commit, KHONG rebase tu dong."
    echo "[sync] Hay chay: git stash && git pull --rebase && git stash pop"
  fi
fi
exit 0
