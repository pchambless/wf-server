#!/bin/bash
# Sync git commits + file changes to agile.git_commits and agile.git_commit_files.
# Runs after git pull, ON the machine that hosts the agile schema.
#
# Configurable via environment variables; the defaults reproduce the original
# hardcoded behaviour exactly, so existing callers need no change:
#   REPO_DIR   checkout to read git history from   (default /home/n8n/wf-server)
#   SYNC_DB    database holding the agile schema   (default n8n)
#   REPO_NAME  value stored in the repo column     (default wf-server)
#
# Example, syncing the sibling repo on the same droplet:
#   REPO_DIR=/home/n8n/wf-marketing REPO_NAME=wf-marketing bash sync-git-commits.sh
#
# NOT usable from the prod droplet as written, for two reasons found 2026-08-14
# (task 248): prod's database has only public, studio and whatsfresh - there is
# no agile schema to write to - and dev's UFW allows 5432 only from 172.28.0.0/16,
# so prod cannot reach dev's Postgres either. This is fine: agile.git_commits is
# repo history, not per-environment history, and this script re-reads the last
# 100 commits with ON CONFLICT DO NOTHING, so anything deployed to prod is
# backfilled by the next dev sync. Recording that a sha is LIVE on prod is a
# deployment fact and belongs in the deployment schema, not here.

: "${REPO_DIR:=/home/n8n/wf-server}"
: "${SYNC_DB:=n8n}"
: "${REPO_NAME:=wf-server}"

DB="$SYNC_DB"
REPO="$REPO_NAME"

cd "$REPO_DIR" || exit 1

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Sync commits (last 100)
git log --format="%H|%s|%an|%ae|%aI" -100 "$BRANCH" | while IFS="|" read -r sha msg author email date; do
  [ -z "$sha" ] && continue
  msg="${msg//\'/\'\'}"
  author="${author//\'/\'\'}"

  sudo -u postgres psql -d "$DB" -q -c "
    INSERT INTO agile.git_commits (sha, message, author, email, commit_date, branch, repo)
    VALUES ('$sha', '$msg', '$author', '$email', '$date', '$BRANCH', '$REPO')
    ON CONFLICT (sha) DO NOTHING;
  " 2>/dev/null
done

# Sync file changes for commits missing file data
MISSING=$(sudo -u postgres psql -d "$DB" -t -A -c "
  SELECT c.sha FROM agile.git_commits c
  LEFT JOIN agile.git_commit_files f ON c.sha = f.sha
  WHERE f.sha IS NULL AND c.repo = '$REPO'
  LIMIT 100;
")

for sha in $MISSING; do
  [ -z "$sha" ] && continue

  # Get the commit body for per-file descriptions
  BODY=$(git log --format="%b" -1 "$sha" 2>/dev/null)

  git diff-tree --no-commit-id -r --numstat "$sha" 2>/dev/null > /tmp/numstat_$$
  git diff-tree --no-commit-id -r --name-status "$sha" 2>/dev/null > /tmp/namestatus_$$

  paste /tmp/numstat_$$ /tmp/namestatus_$$ | while read -r ins del filepath status filepath2; do
    [ -z "$filepath" ] && continue
    ins="${ins//-/0}"
    del="${del//-/0}"
    filepath="${filepath//\'/\'\'}"
    # status: A=Added, M=Modified, D=Deleted, R=Renamed
    status="${status:0:1}"

    # Extract description from commit body: match "- filename: description" or "- filepath: description"
    desc=""
    basename=$(basename "$filepath")
    if [ -n "$BODY" ]; then
      # Try matching by basename (e.g., "- actionHandlers.js: Added conditional...")
      desc=$(echo "$BODY" | grep -i "^- .*${basename}" | head -1 | sed 's/^- [^:]*: *//')
      # If no match by basename, try by full path
      if [ -z "$desc" ]; then
        desc=$(echo "$BODY" | grep -i "^- .*${filepath}" | head -1 | sed 's/^- [^:]*: *//')
      fi
    fi
    desc="${desc//\'/\'\'}"

    sudo -u postgres psql -d "$DB" -q -c "
      INSERT INTO agile.git_commit_files (sha, file_path, status, insertions, deletions, description)
      VALUES ('$sha', '$filepath', '$status', ${ins:-0}, ${del:-0}, $([ -n "$desc" ] && echo "'$desc'" || echo "NULL"));
    " 2>/dev/null
  done

  rm -f /tmp/numstat_$$ /tmp/namestatus_$$
done

echo "[sync-git-commits] Synced commits + files for $REPO ($BRANCH)"
