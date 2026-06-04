#!/usr/bin/env bash
#
# Initializes this template into a concrete Go module (POSIX counterpart of
# init.ps1 — use whichever matches your shell; both do the same thing).
#
# Replaces the placeholder tokens (__ProjectName__, __GoPackage__, __Author__,
# __AuthorEmail__, __GitHubOwner__, __Description__, __Year__) in file contents AND
# in file/folder names, then removes the template-only files (TEMPLATE.md,
# docs/AGENT-INIT-GUIDE.md) and — unless --keep-script — both initializers.
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

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
self="$script_dir/$(basename "$0")"
sibling_ps1="$script_dir/init.ps1"

echo "==> Initializing template as '$slug' (package '$go_package')"

# Literal, backslash-safe token replacement via awk ENVIRON: it does no escape
# processing and no record splitting, so backslashes and trailing newlines in any
# value survive intact (unlike bash's ${var//pat/repl}). Go has no quoted-string
# manifest fields for these values, so no per-file-type escaping is needed.
substitute_tokens() {
  awk '
    function repl(s, tok, val,   out, i) {
      out = ""
      while ((i = index(s, tok)) > 0) {
        out = out substr(s, 1, i - 1) val
        s = substr(s, i + length(tok))
      }
      return out s
    }
    BEGIN {
      s = ENVIRON["TPL_SRC"]
      s = repl(s, "__ProjectName__", ENVIRON["TPL_PROJECT"])
      s = repl(s, "__GoPackage__",   ENVIRON["TPL_PACKAGE"])
      s = repl(s, "__Author__",      ENVIRON["TPL_AUTHOR"])
      s = repl(s, "__AuthorEmail__", ENVIRON["TPL_AUTHOR_EMAIL"])
      s = repl(s, "__GitHubOwner__", ENVIRON["TPL_OWNER"])
      s = repl(s, "__Description__", ENVIRON["TPL_DESC"])
      s = repl(s, "__Year__",        ENVIRON["TPL_YEAR"])
      printf "%s", s
    }'
}

# 1) Replace tokens in file contents. Both initializers are skipped: they carry the
#    literal token strings as search keys, so substituting inside them would corrupt
#    the sibling script.
changed=0
while IFS= read -r -d '' file; do
  case "$file" in
    "$self"|"$sibling_ps1") continue ;;
  esac
  # Skip binary files (NUL bytes get stripped through command substitution).
  case "$file" in
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.zip) continue ;;
  esac
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
done < <(find "$repo_root" -type d \( -name .git -o -name .jj -o -name vendor \) -prune -o -type f -print0)
echo "    Updated contents in $changed file(s)."

# 2) Rename files and folders whose name contains the project-name token. -depth
#    processes children before parents. The flat Go layout has none, but a
#    cmd/__ProjectName__ adaptation would, so support it.
while IFS= read -r -d '' item; do
  case "$item" in
    */.git/*|*/.jj/*|*/vendor/*) continue ;;
  esac
  dir="$(dirname "$item")"
  base="$(basename "$item")"
  newbase="${base//__ProjectName__/$slug}"
  if [ "$newbase" != "$base" ]; then
    mv "$item" "$dir/$newbase"
    echo "    Renamed $base -> $newbase"
  fi
done < <(find "$repo_root" -depth -name '*__ProjectName__*' -print0)

# 3) Activate the Claude Code shared settings.
if [ -f "$repo_root/.claude/settings.json.template" ]; then
  mv -f "$repo_root/.claude/settings.json.template" "$repo_root/.claude/settings.json"
  echo "    Activated .claude/settings.json"
fi

# 4) Remove template-only files.
rm -f "$repo_root/TEMPLATE.md" "$repo_root/docs/AGENT-INIT-GUIDE.md"
rmdir "$repo_root/docs" 2>/dev/null || true

echo ""
echo "Done. Next steps:"
echo "  1. go build ./... && go test ./..."
echo "  2. gofmt -w . && go vet ./..."
echo "  3. Review LICENSE (author/year) and the module path in go.mod."
echo "  4. Replace greeter.go (and greeter_test.go) with your real API."
echo "  5. Releasing: push a vX.Y.Z tag — no secret needed (proxy.golang.org and"
echo "     pkg.go.dev pick it up). Delete .github/workflows/release.yml if not publishing."
echo "  6. Fill the Architecture section of CLAUDE.md, then commit."

# 5) Remove both initializers unless asked to keep them.
if [ "$keep_script" -ne 1 ]; then
  rm -f "$sibling_ps1"
  rm -f "$self"
fi
