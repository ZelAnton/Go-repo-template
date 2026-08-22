#!/usr/bin/env bash
#
# Initializes this template into a concrete Go module (POSIX counterpart of
# init.ps1 — use whichever matches your shell; both do the same thing).
#
# Replaces the placeholder tokens (__ProjectName__, __GoPackage__, __Author__,
# __AuthorEmail__, __GitHubOwner__, __Description__, __Year__) in file contents AND
# in file/folder names, then removes the template-only files (TEMPLATE.md,
# docs/AGENT-INIT-GUIDE.md and the disposable initializer test harness) and —
# unless --keep-script — both initializers.
# Changes are prepared in a staging tree and committed with rollback protection.
#
# Usage:
#   bash ./scripts/init.sh --project-name my-widgets \
#       [--author "Jane Doe"] [--author-email you@example.com] \
#       [--github-owner acme] [--description "A small module"] \
#       [--year 2026] [--keep-script]
#
# --project-name is required; the rest fall back to sensible defaults so the
# result always builds. Two values are derived from it:
#   * a module slug (lowercased, runs of non-alphanumerics -> '-', e.g.
#     "Acme.Widgets" -> "acme-widgets") substituted for __ProjectName__ — the
#     go.mod module-path element, the repository URLs, and any token-named
#     files/folders. Name your GitHub repo with the slug, or edit go.mod after.
#   * a Go package identifier (lowercased, alphanumerics only, e.g. "acmewidgets")
#     substituted for __GoPackage__ — the `package` declarations.
# The slug must start with a letter (a leading digit makes a poor import-path
# element and package name); init errors if it does not.

set -euo pipefail

project_name=""
author=""
author_email=""
github_owner=""
description=""
year=""
keep_script=0

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project-name) project_name="${2:-}"; shift 2 ;;
    --author)       author="${2:-}"; shift 2 ;;
    --author-email) author_email="${2:-}"; shift 2 ;;
    --github-owner) github_owner="${2:-}"; shift 2 ;;
    --description)  description="${2:-}"; shift 2 ;;
    --year)         year="${2:-}"; shift 2 ;;
    --keep-script)  keep_script=1; shift ;;
    -h|--help)      sed -n '2,26p' "$0"; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[ -n "$project_name" ] || die "--project-name is required (e.g. --project-name my-widgets)."

# Module slug: lowercase, runs of non-alphanumerics -> '-', trim leading/trailing '-'.
slug="$(printf '%s' "$project_name" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//')"
[ -n "$slug" ] || die "invalid --project-name '$project_name'. It must contain at least one ASCII letter or digit (e.g. my-widgets)."
case "$slug" in
  [a-z]*) : ;;
  *) die "invalid --project-name '$project_name' -> derived module slug '$slug' starts with a non-letter. Pick a name whose first alphanumeric is a letter (e.g. my-widgets)." ;;
esac
# Go package identifier: lowercase, drop every non-alphanumeric (Go package names
# are single lowercase words — no '-' or '_').
go_package="$(printf '%s' "$project_name" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]//g')"
# Reject a package name Go can't use for a library: any of the 25 reserved
# keywords (a syntax error in `package X`) or "main" (which would make this an
# executable package expecting func main). The slug is unaffected — only the
# package identifier is constrained.
case " break case chan const continue default defer else fallthrough for func go goto if import interface map main package range return select struct switch type var " in
  *" $go_package "*) die "invalid --project-name '$project_name' -> derived Go package name '$go_package' is a Go keyword (or 'main'), which cannot name a library package. Pick a different project name (e.g. prefix it: 'go-$go_package')." ;;
esac

# Defaults (mirror init.ps1).
if [ -z "$author" ]; then
  author="$(git config user.name 2>/dev/null || true)"
  [ -n "$author" ] || author="Your Name"
fi
if [ -z "$author_email" ]; then
  author_email="$(git config user.email 2>/dev/null || true)"
  [ -n "$author_email" ] || author_email="you@example.com"
fi
[ -n "$github_owner" ] || github_owner="your-org"
[ -n "$description" ]  || description="TODO: project description"
[ -n "$year" ]         || year="$(date +%Y)"

validate_release_value() {
  local parameter_name="$1"
  local value="$2"
  [ -n "$value" ] || die "invalid --$parameter_name. It must not be empty or contain control characters (including quotes, backslashes, or newlines)."

  case "$value" in
    *$'\n'*|*$'\r'*|*$'\t'*)
      die "invalid --$parameter_name. It must not be empty or contain control characters (including quotes, backslashes, or newlines)."
      ;;
  esac
  # Consume the complete stream: grep -q can close the pipe early, causing
  # printf to receive SIGPIPE and making pipefail hide a matching control byte.
  if printf '%s' "$value" | LC_ALL=C grep '[[:cntrl:]]' >/dev/null; then
    die "invalid --$parameter_name. It must not be empty or contain control characters (including quotes, backslashes, or newlines)."
  fi
  # These characters could terminate the workflow's POSIX shell/YAML string or
  # introduce expansion. Single quotes remain valid in the surrounding shell
  # double-quoted value, so ordinary names such as O'Connor are accepted.
  case "$value" in
    *'"'*|*'\'*|*'$'*|*'`'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'{'*|*'}'*|*'['*|*']'*|*'!'*|*'*'*|*'?'*)
      die "invalid --$parameter_name '$value'. It contains a character that is unsafe in the generated release workflow."
      ;;
  esac
}

validate_release_value "author" "$author"
validate_release_value "author-email" "$author_email"
validate_release_value "github-owner" "$github_owner"
[[ "$author_email" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || die "invalid --author-email '$author_email'. Supply an email address such as you@example.com."
[[ "$github_owner" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]] || die "invalid --github-owner '$github_owner'. It must be 1-39 ASCII letters, digits, or interior hyphens."

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
self="$script_dir/$(basename "$0")"
sibling_ps1="$script_dir/init.ps1"
test_harness="$script_dir/test-init.sh"
parent_root="$(dirname "$repo_root")"
transaction_prefix=".$(basename "$repo_root").init-backup"

# Fail closed before recovery or staging if strict UTF-8 validation is unavailable.
# POSIX and Git Bash provide iconv; continuing without it could rewrite invalid
# byte sequences that the PowerShell initializer preserves.
utf8_validator="$(command -v iconv 2>/dev/null || true)"
[ -n "$utf8_validator" ] || die "iconv is required for strict UTF-8 validation. Install iconv and rerun."

# TEMPLATE_INIT_FAIL_AT is a disposable-test hook. Preparation failures and a
# partial evacuation must roll back byte-for-byte; a deliberately interrupted
# restore must preserve the remaining originals in the reported backup tree.
failure_stage="${TEMPLATE_INIT_FAIL_AT:-}"
stage_root=""
backup_root=""
swap_started=0
swap_complete=0
rollback_complete=0
original_entries=()
staged_entries=()
evacuated_paths=()
installed_paths=()

fail_at() {
  if [ "$failure_stage" = "$1" ]; then
    die "injected initializer failure at stage '$1'"
  fi
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

recover_unresolved_backup() {
  local candidates=() backup entry name relative target
  local recovered_paths=()

  while IFS= read -r -d '' backup; do
    candidates+=("$backup")
  done < <(find "$parent_root" -mindepth 1 -maxdepth 1 -type d -name "$transaction_prefix*" -print0)

  if [ "${#candidates[@]}" -gt 1 ]; then
    die "found ${#candidates[@]} unresolved initializer backups beside '$repo_root'; refusing to choose one automatically"
  fi
  [ "${#candidates[@]}" -eq 1 ] || return 0

  backup="${candidates[0]}"
  echo "==> Recovering interrupted rollback from '$backup'"

  # Ordinary scripts entries are backed up below a scripts container because the
  # live scripts directory itself must remain in place while an initializer runs.
  if [ -d "$backup/scripts" ]; then
    mkdir -p -- "$repo_root/scripts"
    while IFS= read -r -d '' entry; do
      name="$(basename "$entry")"
      relative="scripts/$name"
      target="$repo_root/$relative"
      if path_exists "$target"; then
        die "cannot recover '$backup': restore target '$target' already exists"
      fi
      mv -- "$entry" "$target" || die "cannot recover '$backup': failed to restore '$relative'"
      recovered_paths+=("$relative")
    done < <(find "$backup/scripts" -mindepth 1 -maxdepth 1 -print0)
    rmdir -- "$backup/scripts" || die "cannot recover '$backup': failed to remove the scripts backup container"
  fi

  while IFS= read -r -d '' entry; do
    name="$(basename "$entry")"
    target="$repo_root/$name"
    if path_exists "$target"; then
      die "cannot recover '$backup': restore target '$target' already exists"
    fi
    mv -- "$entry" "$target" || die "cannot recover '$backup': failed to restore '$name'"
    recovered_paths+=("$name")
  done < <(find "$backup" -mindepth 1 -maxdepth 1 -print0)

  for relative in "${recovered_paths[@]}"; do
    path_exists "$repo_root/$relative" || die "cannot verify restored entry '$repo_root/$relative'; backup remains at '$backup'"
  done
  if find "$backup" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    die "cannot verify that recovery backup '$backup' is empty"
  fi
  rmdir -- "$backup" || die "cannot remove verified recovery backup '$backup'"
}

rollback_swap() {
  local relative saved target restore_moves=0
  for relative in "${installed_paths[@]}"; do
    target="$repo_root/$relative"
    if path_exists "$target"; then
      rm -rf -- "$target" || return 1
    fi
    if path_exists "$target"; then
      echo "error: rollback could not remove installed entry '$target'" >&2
      return 1
    fi
  done
  for relative in "${evacuated_paths[@]}"; do
    saved="$backup_root/$relative"
    target="$repo_root/$relative"
    if ! path_exists "$saved"; then
      echo "error: rollback backup entry is missing: '$saved'" >&2
      return 1
    fi
    if path_exists "$target"; then
      echo "error: rollback restore target already exists: '$target'" >&2
      return 1
    fi
    mkdir -p -- "$(dirname "$target")" || return 1
    mv -- "$saved" "$target" || return 1
    restore_moves=$((restore_moves + 1))
    if [ "$failure_stage" = restore ] && [ "$restore_moves" -eq 1 ]; then
      echo "error: injected initializer failure at stage 'restore'" >&2
      return 1
    fi
  done
  for relative in "${evacuated_paths[@]}"; do
    if path_exists "$backup_root/$relative" || ! path_exists "$repo_root/$relative"; then
      echo "error: rollback could not verify restored entry '$relative'" >&2
      return 1
    fi
  done
  rollback_complete=1
}

apply_scripts_stage() {
  local live_scripts="$repo_root/scripts"
  local staged_scripts="$stage_root/scripts"
  local entry name relative target
  local script_evacuations=0 script_installs=0

  mkdir -p -- "$live_scripts" "$backup_root/scripts"

  # Keep the live directory and runtime scripts in place. Only ordinary direct
  # children move; a token-named directory carries its transformed descendants.
  while IFS= read -r -d '' entry; do
    name="$(basename "$entry")"
    case "$name" in
      init.sh|init.ps1|test-init.sh) continue ;;
    esac
    relative="scripts/$name"
    mv -- "$entry" "$backup_root/$relative"
    evacuated_paths+=("$relative")
    script_evacuations=$((script_evacuations + 1))
    if [ "$failure_stage" = remove-scripts ] && [ "$script_evacuations" -eq 1 ]; then
      die "injected initializer failure at stage 'remove-scripts'"
    fi
  done < <(find "$live_scripts" -mindepth 1 -maxdepth 1 -print0)

  while IFS= read -r -d '' entry; do
    name="$(basename "$entry")"
    case "$name" in
      init.sh|init.ps1|test-init.sh) continue ;;
    esac
    relative="scripts/$name"
    target="$repo_root/$relative"
    if path_exists "$target"; then
      die "cannot install staged script entry '$relative': target '$target' already exists"
    fi
    mv -- "$entry" "$target"
    installed_paths+=("$relative")
    script_installs=$((script_installs + 1))
    if [ "$failure_stage" = scripts ] && [ "$script_installs" -eq 1 ]; then
      die "injected initializer failure at stage 'scripts'"
    fi
  done < <(find "$staged_scripts" -mindepth 1 -maxdepth 1 -print0)
}

cleanup_transaction() {
  local status=$?
  trap - EXIT
  if [ "$swap_complete" -eq 0 ] && [ "$swap_started" -eq 1 ]; then
    if ! rollback_swap; then
      echo "error: initializer failed and rollback also failed; original entries remain recoverable at '$backup_root'" >&2
      status=1
    fi
  fi
  if [ -n "$stage_root" ] && path_exists "$stage_root"; then
    rm -rf -- "$stage_root" || status=1
  fi
  if [ -n "$backup_root" ] && path_exists "$backup_root"; then
    if [ "$swap_started" -eq 0 ] || [ "$swap_complete" -eq 1 ] || [ "$rollback_complete" -eq 1 ]; then
      rm -rf -- "$backup_root" || status=1
    else
      echo "error: preserving incomplete rollback backup at '$backup_root'" >&2
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup_transaction EXIT

recover_unresolved_backup

echo "==> Initializing template as '$slug' (package '$go_package')"

# Literal, backslash-safe token replacement via awk ENVIRON: it does no escape
# processing and no record splitting. Author and email have already been checked
# for the shell/YAML context used by release.yml; the remaining values are either
# derived identifiers or plain-text fields.
substitute_tokens() {
  awk '
    function replacement(token) {
      if (token == "__ProjectName__") return ENVIRON["TPL_PROJECT"]
      if (token == "__GoPackage__") return ENVIRON["TPL_PACKAGE"]
      if (token == "__Author__") return ENVIRON["TPL_AUTHOR"]
      if (token == "__AuthorEmail__") return ENVIRON["TPL_AUTHOR_EMAIL"]
      if (token == "__GitHubOwner__") return ENVIRON["TPL_OWNER"]
      if (token == "__Description__") return ENVIRON["TPL_DESC"]
      return ENVIRON["TPL_YEAR"]
    }
    BEGIN {
      s = ENVIRON["TPL_SRC"]
      out = ""
      while (match(s, /__ProjectName__|__GoPackage__|__Author__|__AuthorEmail__|__GitHubOwner__|__Description__|__Year__/)) {
        token = substr(s, RSTART, RLENGTH)
        out = out substr(s, 1, RSTART - 1) replacement(token)
        s = substr(s, RSTART + RLENGTH)
      }
      printf "%s%s", out, s
    }'
}

# Prepare all mutable files in an adjacent staged tree. The initializer files and
# disposable harness are copied byte-for-byte and left untouched until cleanup.
stage_root="$(mktemp -d "$parent_root/.$(basename "$repo_root").init-stage.XXXXXXXX")"
while IFS= read -r -d '' entry; do
  name="$(basename "$entry")"
  case "$name" in
    .git|.jj|vendor) continue ;;
  esac
  cp -a -- "$entry" "$stage_root/"
done < <(find "$repo_root" -mindepth 1 -maxdepth 1 -print0)
fail_at copy

# 1) Replace tokens in file contents. The initializer scripts and test harness
#    remain byte-for-byte copies, so their literal search keys cannot be corrupted.
changed=0
while IFS= read -r -d '' file; do
  case "$file" in
    "$stage_root/scripts/init.sh"|"$stage_root/scripts/init.ps1"|"$stage_root/scripts/test-init.sh") continue ;;
    "$stage_root/.claude/settings.json") continue ;;
  esac
  # Substitute only supported UTF-8 text formats. Unknown asset types stay
  # byte-for-byte untouched instead of relying on a binary extension denylist.
  name="$(basename "$file" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    .editorconfig|.gitattributes|.gitignore|codeowners|dockerfile|license|makefile|\
    *.bat|*.cmd|*.go|*.json|*.md|*.mod|*.ps1|*.psd1|*.psm1|*.sh|*.sum|\
    *.template|*.toml|*.txt|*.yaml|*.yml) ;;
    *) continue ;;
  esac
  # Skip mixed content before command substitution can strip embedded NUL bytes.
  if ! LC_ALL=C tr -d '\000' < "$file" | cmp -s - "$file"; then
    continue
  fi
  # Reject malformed UTF-8 before bytes enter shell/environment variables.
  if ! "$utf8_validator" -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1; then
    continue
  fi
  # Preserve trailing newlines: append a sentinel before capture, strip it after.
  content="$(cat "$file"; printf x)"; content="${content%x}"
  new="$(TPL_SRC="$content" TPL_PROJECT="$slug" TPL_PACKAGE="$go_package" \
         TPL_AUTHOR="$author" TPL_AUTHOR_EMAIL="$author_email" TPL_OWNER="$github_owner" \
         TPL_DESC="$description" TPL_YEAR="$year" substitute_tokens; printf x)"
  new="${new%x}"
  if [ "$new" != "$content" ]; then
    printf '%s' "$new" > "$file"
    changed=$((changed + 1))
  fi
done < <(find "$stage_root" -type d \( -name .git -o -name .jj -o -name vendor \) -prune -o -type f -print0)
echo "    Updated contents in $changed file(s)."
fail_at content

# 2) Rename files and folders whose name contains the project-name token. -depth
#    processes children before parents. The flat Go layout has none, but a
#    cmd/__ProjectName__ adaptation would, so support it.
while IFS= read -r -d '' item; do
  case "$item" in
    */.git/*|*/.jj/*|*/vendor/*) continue ;;
    "$stage_root/scripts/init.sh"|"$stage_root/scripts/init.ps1"|"$stage_root/scripts/test-init.sh") continue ;;
  esac
  dir="$(dirname "$item")"
  base="$(basename "$item")"
  newbase="${base//__ProjectName__/$slug}"
  if [ "$newbase" != "$base" ]; then
    if path_exists "$dir/$newbase"; then
      die "cannot rename '$item': target '$dir/$newbase' already exists"
    fi
    mv "$item" "$dir/$newbase"
    echo "    Renamed $base -> $newbase"
  fi
done < <(find "$stage_root" -depth -name '*__ProjectName__*' -print0)
fail_at rename

# 3) Activate shared settings only when no user config already exists in the
#    staged tree. Existing settings are immutable input and remain byte-for-byte.
if [ -f "$stage_root/.claude/settings.json" ]; then
  echo "    Preserved existing .claude/settings.json."
elif [ -f "$stage_root/.claude/settings.json.template" ]; then
  mv -f "$stage_root/.claude/settings.json.template" "$stage_root/.claude/settings.json"
  echo "    Activated .claude/settings.json"
fi
fail_at activate

# 4) Remove template-only files from the staged tree.
rm -f "$stage_root/TEMPLATE.md" "$stage_root/docs/AGENT-INIT-GUIDE.md"
rmdir "$stage_root/docs" 2>/dev/null || true
fail_at delete

# Commit the prepared top-level tree by moving mutable entries to an adjacent
# backup, then moving staged entries into place. scripts/ is applied separately so
# its live directory and runtime files never move while an initializer runs.
while IFS= read -r -d '' entry; do
  name="$(basename "$entry")"
  case "$name" in
    .git|.jj|vendor|scripts) continue ;;
  esac
  original_entries+=("$name")
done < <(find "$repo_root" -mindepth 1 -maxdepth 1 -print0)
while IFS= read -r -d '' entry; do
  name="$(basename "$entry")"
  [ "$name" = scripts ] && continue
  staged_entries+=("$name")
done < <(find "$stage_root" -mindepth 1 -maxdepth 1 -print0)
backup_root="$(mktemp -d "$parent_root/.$(basename "$repo_root").init-backup.XXXXXXXX")"
swap_started=1
for relative in "${original_entries[@]}"; do
  mkdir -p -- "$(dirname "$backup_root/$relative")"
  mv -- "$repo_root/$relative" "$backup_root/$relative"
  evacuated_paths+=("$relative")
  if [ "$failure_stage" = evacuate ] && [ "${#evacuated_paths[@]}" -eq 1 ]; then
    die "injected initializer failure at stage 'evacuate'"
  fi
done
commit_moves=0
for relative in "${staged_entries[@]}"; do
  mkdir -p -- "$(dirname "$repo_root/$relative")"
  mv -- "$stage_root/$relative" "$repo_root/$relative"
  installed_paths+=("$relative")
  commit_moves=$((commit_moves + 1))
  if { [ "$failure_stage" = commit ] || [ "$failure_stage" = restore ]; } && [ "$commit_moves" -eq 1 ]; then
    die "injected initializer failure at stage '$failure_stage'"
  fi
done
apply_scripts_stage
swap_complete=1

echo ""
echo "Done. Next steps:"
echo "  1. go build ./... && go test ./..."
echo "  2. gofmt -w . && go vet ./..."
echo "  3. Review LICENSE (author/year) and the module path in go.mod."
echo "  4. Replace greeter.go (and greeter_test.go) with your real API."
echo "  5. Releasing: push a vX.Y.Z tag — no secret needed (proxy.golang.org and"
echo "     pkg.go.dev pick it up). Delete .github/workflows/release.yml if not publishing."
echo "  6. Fill the Architecture section of CLAUDE.md, then commit."

# These are the only live-tree deletions. They happen after the swap, so a locked
# file leaves a complete initialized tree that is safe to retry.
if [ "$keep_script" -ne 1 ]; then
  rm -f "$test_harness" "$sibling_ps1"
  rm -f "$self"
else
  rm -f "$test_harness"
fi
