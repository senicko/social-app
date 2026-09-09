#!/usr/bin/env bash

# pr.sh
#
# Open or update the before/after PR with both screenshots in the body's HTML
# table. Screenshots go up with gh --attach, which hosts them as GitHub assets.
# gh rewrites markdown references but not HTML, and markdown inside an HTML
# table is not rendered, so: upload with a helper markdown link per screenshot,
# read the rewritten URLs back, re-send the body with them in the <img src>.
#
# Commands
#   create <title> [body-file]    Push the branch if it has no upstream, create the
#                                 PR with both screenshots, fill the table, check
#   update [number] [body-file]   Upload both screenshots again and rewrite the
#                                 body of an existing PR the same way, then check
#   check [number]                Verify the body: two asset URLs, no ./media left
#
# Files, from screenshot.sh
#   media/before.png  media/after.png
#
# Env
#   PR_BASE     Base branch for create (default main)
#   PR_MAX_MB   Size limit per attachment (default 10, GitHub Free)
#   DRY_RUN=1   Print the gh and git commands instead of running them

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${PR_BASE:-main}"
MAX_MB="${PR_MAX_MB:-10}"
BODY_DEFAULT="pr-body.md"
NAMES=(before.png after.png)
ASSET_RE='https://github\.com/user-attachments/assets/[A-Za-z0-9_./-]*'

dry() { [ "${DRY_RUN:-}" = 1 ]; }

check_media() {
  local n f bytes limit=$((MAX_MB * 1000 * 1000)) ok=1

  for n in "${NAMES[@]}"; do
    f="media/$n"

    if [ ! -s "$f" ]; then
      echo "missing: $f (bash .cursor/cloud/screenshot.sh ${n%.png} writes it)" >&2; ok=0; continue
    fi

    bytes="$(wc -c < "$f" | tr -d ' ')"

    if [ "$bytes" -gt "$limit" ]; then
      echo "$f is $((bytes / 1000)) kB, over the $MAX_MB MB limit" >&2; ok=0
    fi
  done

  [ "$ok" = 1 ] || exit 1
}

check_body() {
  local body="$1" n

  [ -f "$body" ] || { echo "$body not found. Copy .cursor/cloud/pr-body.md to $body and fill it in." >&2; exit 1; }

  if grep -q 'BUILD_ID' "$body"; then
    echo "warning: $body still contains the BUILD_ID placeholder" >&2
  fi

  # Only URLs on a cursor host or the artifacts mount; prose may mention Cursor.
  if grep -qiE 'https?://[^/ )]*cursor[^/ )]*/|/opt/cursor/artifacts' "$body"; then
    echo "$body references Cursor artifacts. GitHub does not render those; keep the ./media paths in the table and let gh attach the files." >&2
    exit 1
  fi

  for n in "${NAMES[@]}"; do
    grep -q "src=\"./media/$n\"" "$body" || { echo "$body has no <img src=\"./media/$n\"> tag. Start from .cursor/cloud/pr-body.md." >&2; exit 1; }
  done
}

# The body as sent on upload: the author's file plus one helper link per
# screenshot. gh rewrites each link to the asset URL, which is how finalize
# learns them. finalize removes the links again.
stage_body() {
  local body="$1" out="$2" n
  {
    cat "$body"
    printf '\n\n<!-- pr.sh: temporary, replaced once the uploads are known -->\n\n'
    for n in "${NAMES[@]}"; do printf -- '- [pr.sh:%s](./media/%s)\n' "$n" "$n"; done
  } > "$out"
}

gh_run() {
  if dry; then
    printf 'DRY_RUN: gh'; printf ' %q' "$@"; printf '\n'
  else
    gh "$@"
  fi
}

pr_body() {
  local num="${1:-}"
  gh pr view ${num:+"$num"} --json body --jq .body
}

# Reads the rewritten helper links back, writes the URLs into the author's
# body and sends that as the final body.
finalize() {
  local num="${1:-}" body="$2" current n url final
  current="$(pr_body "$num")"
  final="$(mktemp)"

  cp "$body" "$final"

  for n in "${NAMES[@]}"; do
    url="$(printf '%s' "$current" | grep -o "\[pr\.sh:$n\]($ASSET_RE)" | head -1 | sed 's/^.*](\(.*\))$/\1/' || true)"

    if [ -z "$url" ]; then
      echo "no asset URL for $n in the PR body; the upload failed or the helper link was edited. Fix media/$n, then: bash .cursor/cloud/pr.sh update ${num:-<number>} $body" >&2
      exit 1
    fi

    sed -i.bak "s|\"\./media/$n\"|\"$url\"|g" "$final" && rm -f "$final.bak"
  done

  gh pr edit ${num:+"$num"} --body-file "$final" >/dev/null
  rm -f "$final"
}

check() {
  local num="${1:-}" current urls n

  current="$(pr_body "$num")"
  urls="$(printf '%s' "$current" | grep -o "<img src=\"$ASSET_RE\"" | grep -o "$ASSET_RE" || true)"
  n="$(printf '%s' "$urls" | grep -c . || true)"
  gh pr view ${num:+"$num"} --json url --jq .url
  [ -z "$urls" ] || echo "$urls"

  if printf '%s' "$current" | grep -q '\./media/\|pr\.sh:'; then
    echo "the body still has ./media paths or pr.sh helper links; the finalize step did not run. Run: bash .cursor/cloud/pr.sh update ${num:-<number>} pr-body.md" >&2
    exit 1
  fi

  if [ "$n" -lt 2 ]; then
    echo "expected 2 <img> tags with asset URLs, found $n. Run: bash .cursor/cloud/pr.sh update ${num:-<number>} pr-body.md" >&2
    exit 1
  fi

  echo "ok: $n screenshots in the Before / After table"
}

case "${1:-}" in
  create)
    title="${2:?usage: pr.sh create <title> [body-file]}"
    body="${3:-$BODY_DEFAULT}"
    branch="$(git rev-parse --abbrev-ref HEAD)"
    [ "$branch" != "$BASE" ] || { echo "you are on $BASE; create the PR from a feature branch" >&2; exit 1; }
    check_body "$body"
    check_media

    if [ -n "$(git status --porcelain -- src)" ]; then
      echo "warning: uncommitted changes under src/; the PR will not include them" >&2
    fi

    if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      if dry; then echo "DRY_RUN: git push -u origin $branch"; else git push -u origin "$branch"; fi
    fi

    staged="$(mktemp)"
    stage_body "$body" "$staged"
    attach=()
    for n in "${NAMES[@]}"; do attach+=(--attach "./media/$n"); done
    gh_run pr create --base "$BASE" --head "$branch" --title "$title" --body-file "$staged" "${attach[@]}"

    if dry; then
      echo "DRY_RUN: staged body tail:"; tail -n 4 "$staged"; rm -f "$staged"
    else
      rm -f "$staged"
      finalize "" "$body"
      check
    fi
    ;;
  update)
    num="${2:-}"
    body="${3:-$BODY_DEFAULT}"
    check_body "$body"
    check_media
    staged="$(mktemp)"
    stage_body "$body" "$staged"
    attach=()
    for n in "${NAMES[@]}"; do attach+=(--attach "./media/$n"); done
    args=(pr edit)

    if [ -n "$num" ]; then args+=("$num"); fi

    gh_run "${args[@]}" --body-file "$staged" "${attach[@]}"

    if dry; then
      rm -f "$staged"
    else
      rm -f "$staged"
      finalize "$num" "$body"
      check "$num"
    fi

    ;;
  check)
    check "${2:-}"
    ;;
  *) echo "usage: $0 create <title> [body-file] | update [number] [body-file] | check [number]" >&2; exit 2 ;;
esac
