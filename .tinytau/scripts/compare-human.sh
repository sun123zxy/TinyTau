#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

HUMAN_REPO="$(yq -r '.["human-repo"] // ""' .tinytau/config.yml)"
HUMAN_DIR="$(yq -r '.["human-directory"] // ""' .tinytau/config.yml | sed 's:^/*::; s:/*$::')"
HUMAN_SHA="$(yq -r '.["human-sha"] // ""' .tinytau/sync.yml)"

echo "human-repo=${HUMAN_REPO} human-directory=/${HUMAN_DIR} human-sha=${HUMAN_SHA}"

AI_REGEX='(.*/)?[^/]*-ai(\.[^/.]*)?$'

if [ -z "${HUMAN_SHA}" ] || [ "${HUMAN_SHA}" = "null" ]; then
  # Before the first sync there is no source commit to compare against.
  # The roadmap may be absent or contain only AI-maintained files.
  if git rev-parse --verify -q HEAD:roadmap >/dev/null; then
    # grep returns 1 if no human files were listed. Handle that status
    # here so pipefail still reports errors from git ls-tree.
    extra="$(git -c core.quotepath=false ls-tree -r --name-only HEAD:roadmap |
      { grep -vE "^${AI_REGEX}" || [ "$?" -eq 1 ]; })"
    if [ -n "${extra}" ]; then
      echo "FAIL: human-sha is null, but human-authored files exist under roadmap/:"
      echo "${extra}"
      exit 1
    fi
  else
    status=$?
    [ "$status" -eq 1 ] || exit "$status"
  fi
  echo "PASS: human-sha is null and roadmap/ has no human-authored files."
  exit 0
fi

if ! git cat-file -e "${HUMAN_SHA}^{commit}" 2>/dev/null; then
  git fetch --depth 1 "https://github.com/${HUMAN_REPO}.git" "${HUMAN_SHA}"
fi

UPSTREAM="${HUMAN_SHA}${HUMAN_DIR:+:${HUMAN_DIR}}"
git rev-parse --verify -q "${UPSTREAM}" >/dev/null || {
  echo "FAIL: ${UPSTREAM} not found"
  exit 1
}

if ! git rev-parse --verify -q HEAD:roadmap >/dev/null; then
  echo "FAIL: roadmap/ directory does not exist in HEAD."
  git -c core.quotepath=false ls-tree -r --name-only "${UPSTREAM}"
  exit 1
fi

# Compare the committed roadmap with its source, ignoring AI-maintained files.
# grep returns 1 if there are no human-file changes. Handle that status
# inside the pipeline so pipefail still reports errors from git diff.
diff_out="$(git -c core.quotepath=false diff --name-status --no-renames "${UPSTREAM}" HEAD:roadmap |
  { grep -vE "^[^[:space:]]+[[:space:]]+${AI_REGEX}" || [ "$?" -eq 1 ]; })"
if [ -n "${diff_out}" ]; then
  echo "FAIL: roadmap/ human-authored files differ from ${UPSTREAM}:"
  echo "${diff_out}"
  exit 1
fi

count="$(git ls-tree -r --name-only "${UPSTREAM}" | wc -l | tr -d ' ')"
echo "PASS: ${count} human-authored files in roadmap/ match ${UPSTREAM} byte-for-byte."
