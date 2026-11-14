#!/usr/bin/env bash
# Builds one stable T3 Code release the way this fork ships it: upstream's own Linux x64
# archive of that release, with its server executable rebuilt from the release's source plus
# the fixes in patches/. With no fix left to carry, the result is upstream's archive itself.
#
#   build.sh <tag> <out-dir>        for example: build.sh v0.1.9 out
#
# Writes <out-dir>/t3-<version>-linux-x64.tar.gz, SHA256SUMS and notes.md.
# Exit 3 means a fix does not fit this release; any other failure is the build's.
#
# Needs git, curl, jq, tar, patchelf, pnpm and the Node the release names in package.json.
# GH_TOKEN, when set, signs the calls to GitHub's API (60 an hour are free without it).
set -euo pipefail

tag=${1:?usage: build.sh <tag> <out-dir>}
mkdir -p "${2:?usage: build.sh <tag> <out-dir>}"
out=$(cd "$2" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
upstream=pingdotgg/t3code
version=${tag#v}
stem=t3-$version-linux-x64
archive=$stem.tar.gz
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

api() {
  curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
    -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
}
say() { printf '\n== %s\n' "$*"; }

say "upstream's archive of $tag, checked against the checksums of its release"
curl -fsSL -o "$work/$archive" "https://github.com/$upstream/releases/download/$tag/$archive"
curl -fsSL "https://github.com/$upstream/releases/download/$tag/SHA256SUMS" |
  grep " $archive\$" | (cd "$work" && sha256sum -c -)

say "the source of $tag"
git clone --quiet --depth 1 --branch "$tag" --filter=blob:none --no-checkout \
  "https://github.com/$upstream.git" "$work/src"
cd "$work/src"
# .repos holds vendored reference copies that no build reads.
git sparse-checkout set --no-cone '/*' '!/.repos/'
git checkout --quiet --detach "$tag"
git config user.name "t3code-fork build"
git config user.email "build@t3code-fork.invalid"

# The release's own tools, only once there is a fix to try: a release that needs none is not built.
tools_ready=
need_tools() {
  [ -z "$tools_ready" ] || return 0
  local node_wanted
  node_wanted=v$(jq -r .engines.node package.json)
  if [ "$(node --version)" != "$node_wanted" ]; then
    echo "$tag builds with Node $node_wanted; this is $(node --version)." >&2
    exit 1
  fi
  pnpm install --frozen-lockfile --filter 't3...' --filter '@t3tools/scripts...'
  export PATH="$PWD/node_modules/.bin:$PATH"
  tools_ready=yes
}

# A fix stands when it applies and the packages it touches still typecheck and pass their tests.
stands() {
  local dir
  for dir in $(git diff --cached --name-only | sed -n 's#^\(packages/[^/]*\|apps/server\)/.*#\1#p' | sort -u); do
    (cd "$dir" && node --run typecheck) > "$work/check.log" 2>&1 || return 1
    case $dir in packages/*) (cd "$dir" && node --run test) > "$work/check.log" 2>&1 || return 1 ;; esac
  done
}

: > "$work/fixes.md"
carried=0
for dir in "$here"/patches/*/; do
  [ -d "$dir" ] || continue
  pr=$(basename "$dir")
  pull=$(api "repos/$upstream/pulls/$pr")
  title=$(jq -r .title <<< "$pull")
  say "$upstream#$pr: $title"
  # A fix upstream merged before this release is in the release already.
  if [ "$(jq -r .merged <<< "$pull")" = true ] &&
    [ "$(api "repos/$upstream/compare/$(jq -r .merge_commit_sha <<< "$pull")...$tag" | jq -r .behind_by)" = 0 ]; then
    echo "in upstream's $tag: not carried"
    echo "- [#$pr](https://github.com/$upstream/pull/$pr) $title: part of upstream's $tag, no longer carried" >> "$work/fixes.md"
    continue
  fi
  need_tools
  fitted=
  for patch in "$dir"*.patch; do
    rm -f "$work/check.log"
    if git apply --index --3way "$patch" > "$work/apply.log" 2>&1 &&
      [ -z "$(git diff --name-only --diff-filter=U)" ] && stands; then
      fitted=$(basename "$patch")
      break
    fi
    echo "$(basename "$patch") does not fit:"
    tail -n 3 "$work/apply.log" "$work/check.log" 2> /dev/null | cut -c1-200 || true
    git reset --quiet --hard
    git clean --quiet -fd -- apps packages
  done
  if [ -z "$fitted" ]; then
    echo "No version of the fix for $upstream#$pr fits $tag. Add one to patches/$pr/." >&2
    exit 3
  fi
  git commit --quiet --no-verify -m "carry $upstream#$pr ($fitted)"
  echo "carried as $fitted"
  echo "- [#$pr](https://github.com/$upstream/pull/$pr) $title" >> "$work/fixes.md"
  carried=$((carried + 1))
done

if [ "$carried" = 0 ]; then
  say "nothing to carry: upstream's archive as it is"
  cp "$work/$archive" "$out/$archive"
  echo "Upstream's own archive of $tag, unchanged: there is no fix left to carry." > "$out/notes.md"
else
  # Only the server executable is rebuilt; the web client and the rest stay upstream's.
  outside=$(git diff --name-only "$tag" HEAD | grep -v -E '^(apps/server|packages)/' || true)
  if [ -n "$outside" ]; then
    echo "A fix changes files this build does not rebuild: $outside" >&2
    exit 1
  fi

  say "the server executable, from $tag with $carried fix(es)"
  # T3 Connect's public settings, as upstream publishes them for builds outside its own pipeline.
  cp .env.example .env
  node scripts/update-release-package-versions.ts "$version"
  T3CODE_TELEMETRY_CHANNEL=dev node apps/server/scripts/cli.ts build-exe

  say "upstream's archive with that executable in it"
  mkdir "$work/unpacked"
  tar -xzf "$work/$archive" -C "$work/unpacked"
  cp apps/server/dist-exe/t3 "$work/unpacked/$stem/t3"
  # As upstream's own packaging does: the executable finds libatomic in lib/ beside it.
  patchelf --set-rpath '$ORIGIN/lib' "$work/unpacked/$stem/t3"
  chmod 755 "$work/unpacked/$stem/t3"
  tar --hard-dereference --sort=name --owner=0 --group=0 --numeric-owner \
    -czf "$out/$archive" -C "$work/unpacked" "$stem"

  say "upstream's smoke test of an archive"
  node scripts/smoke-cli-archive.ts --archive "$out/$archive" --expect-version "$version"
  echo "Upstream's archive of $tag, with its server executable rebuilt from $tag plus these fixes:" > "$out/notes.md"
fi
{ echo; cat "$work/fixes.md"; } >> "$out/notes.md"

(cd "$out" && sha256sum "$archive" > SHA256SUMS)
say "done: $(cat "$out/SHA256SUMS")"
