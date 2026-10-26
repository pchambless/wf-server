#!/usr/bin/env bash
# RUNS LOCALLY. Pushes every WhatsFresh repo that is ahead of its remote. Agents are blocked from pushing, so this is
# the one command Paul runs.
#
# Usage: bash scripts/push-all.sh            fetch, report, push what is strictly ahead
#        bash scripts/push-all.sh --check    fetch and report only, push nothing
#
# Safety: plain `git push` of the CURRENT branch to its own upstream only. Never --force, never pulls or merges. A repo that is
# behind, diverged, detached, or has no upstream is reported and skipped. Uncommitted tracked changes are only warned about.
set -u

CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
BASE="$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")"
REPOS="wf-server wf-agents support-app app-engine wf-marketing"
PUSHED=0; SKIPPED=0; FAILED=0

for r in $REPOS; do
  d="$BASE/$r"
  [ -d "$d/.git" ] || continue
  echo "== $r"
  git -C "$d" fetch -q origin 2>/dev/null || { echo "   fetch failed (network?), skipping"; FAILED=$((FAILED+1)); continue; }
  branch="$(git -C "$d" branch --show-current)"
  if [ -z "$branch" ]; then echo "   detached HEAD, skipping"; SKIPPED=$((SKIPPED+1)); continue; fi
  if ! git -C "$d" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    echo "   branch $branch has no upstream, skipping"; SKIPPED=$((SKIPPED+1)); continue
  fi
  ahead="$(git -C "$d" rev-list --count '@{u}..HEAD')"
  behind="$(git -C "$d" rev-list --count 'HEAD..@{u}')"
  dirty="$(git -C "$d" status --short | grep -vc '^??' || true)"
  [ "$dirty" -gt 0 ] && echo "   note: $dirty uncommitted tracked file(s), not pushed (git only pushes commits)"
  if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
    echo "   $branch DIVERGED (ahead $ahead, behind $behind): not pushing, sort this one out by hand"; SKIPPED=$((SKIPPED+1)); continue
  elif [ "$behind" -gt 0 ]; then
    echo "   $branch is behind by $behind: pull first, not pushing"; SKIPPED=$((SKIPPED+1)); continue
  elif [ "$ahead" -eq 0 ]; then
    echo "   $branch up to date"; continue
  fi
  echo "   $branch ahead by $ahead:"
  git -C "$d" log --oneline '@{u}..HEAD' | cut -c1-110 | sed 's/^/     /'
  if [ "$CHECK" -eq 1 ]; then echo "   (--check: not pushing)"; continue; fi
  if git -C "$d" push -q 2>&1 | sed 's/^/   /'; [ "${PIPESTATUS[0]}" -eq 0 ]; then
    echo "   pushed"; PUSHED=$((PUSHED+1))
  else
    echo "   PUSH FAILED"; FAILED=$((FAILED+1))
  fi
done
echo
echo "pushed $PUSHED repo(s), skipped $SKIPPED, failed $FAILED$([ "$CHECK" -eq 1 ] && echo '  (check only)')"
[ "$FAILED" -eq 0 ]
