# T3 Code, with fixes upstream has not shipped yet

This is a fork of [pingdotgg/t3code](https://github.com/pingdotgg/t3code). It exists to run
stable T3 Code releases with a few fixes before upstream ships them. It follows upstream by
itself: nobody merges anything here by hand.

## What it publishes

For each stable release of upstream, a [release here](../../releases) named
`<upstream tag>-t3kube.<n>` with:

- `t3-<version>-linux-x64.tar.gz`: upstream's own archive of that release, with its server
  executable rebuilt from the release's source plus the fixes in [`patches/`](patches). The
  web client, the native modules and everything else in the archive are upstream's files.
- `SHA256SUMS` for it.

Its notes list the fixes that build carries. [`builds.md`](builds.md) lists the builds.

When no fix is left to carry, the release holds upstream's archive unchanged.

## How it follows upstream

[A workflow](.github/workflows/follow-upstream.yml) runs every three hours. It asks upstream
for its latest stable release and, if this fork has no build of it with the current fixes,
runs [`build.sh`](build.sh) and publishes the result.

`patches/` has one folder per upstream pull request, named by its number. For a release:

- a pull request that upstream merged before that release is skipped: the release has it;
- otherwise the files in its folder are tried in name order, and the first that applies and
  leaves the packages it touches passing their typecheck and tests is used. Several files are
  the same fix written for different releases.

If no file of a folder fits a release, that run fails, GitHub notifies the owner, and no build
of that release appears until `patches/` changes. Earlier builds stay as they are.

## Changing what it carries

- **Carry another fix**: add `patches/<upstream PR number>/1-<name>.patch`, a `git diff` of
  the fix against the release it is for. A fix may only change `apps/server` and `packages`:
  nothing else is rebuilt.
- **A fix does not fit a new release**: add a second file to its folder with the fix written
  for that release.
- **Stop carrying a fix**: delete its folder. This is not needed once upstream ships it.

A change to `patches/` or `build.sh` makes the next run build the latest release again, as
build `n+1`. To build another release, run the workflow by hand with its tag.

## The fixes' own branches

The `fix/…` branches here are the heads of the pull requests on upstream. `main` is where
upstream's `main` was when the fork was made, and is not updated.
