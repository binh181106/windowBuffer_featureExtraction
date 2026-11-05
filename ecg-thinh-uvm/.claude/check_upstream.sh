#!/usr/bin/env bash
# Canh bao neu origin/main da tien trong luc dang code.
cd "$(git rev-parse --show-toplevel)" 2>/dev/null || exit 0
REMOTE=$(git ls-remote origin refs/heads/main 2>/dev/null | cut -f1)
LOCAL=$(git rev-parse origin/main 2>/dev/null)
if [ -n "$REMOTE" ] && [ -n "$LOCAL" ] && [ "$REMOTE" != "$LOCAL" ]; then
  echo "[upstream] origin/main da co commit moi (${REMOTE:0:8} != ${LOCAL:0:8})."
  echo "[upstream] Hay chay: git fetch && git rebase origin/main"
fi
exit 0
