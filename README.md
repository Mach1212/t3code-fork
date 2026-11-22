# T3 Code, with what upstream's releases do not have yet

This is a fork of [pingdotgg/t3code](https://github.com/pingdotgg/t3code). It exists to run
stable T3 Code releases with a few changes that those releases do not have. It follows upstream
by itself: nobody merges anything here by hand.

## What it publishes

For each stable release of upstream, a [release here](../../releases) named
`<upstream tag>-t3kube.<n>` with:

- `t3-<version>-linux-x64.tar.gz`: upstream's own archive of that release, with its server
  executable rebuilt from the release's source plus the changes in [`patches/`](patches). The
  web client, the native modules and everything else in the archive are upstream's files.
- `SHA256SUMS` for it.

Its notes list what that build carries. [`builds.md`](builds.md) lists the builds.

When nothing is left to carry, the release holds upstream's archive unchanged.

## What it carries

- **Fixes that upstream has merged or replaced, until a stable release has them.** Their folders
  in `patches/` are named by the number of the pull request on upstream.

## How it follows upstream

[A workflow](.github/workflows/follow-upstream.yml) runs every three hours. It asks upstream
for its latest stable release and, if this fork has no build of it with what `patches/` holds
now, runs [`build.sh`](build.sh) and publishes the result.

`patches/` has one folder per change. For a release:

- a folder named by a number is a pull request of upstream. It is skipped once upstream merged
  it before that release: the release has it. It is skipped too once the release has the pull
  request named in its file `superseded-by`, with which upstream fixed the same problem;
- a folder with any other name is this fork's own, and is carried for as long as it is there.
  The first line of its file `title` names it in a build's notes;
- the `.patch` files of a folder are tried in name order, and the first that applies and
  leaves the packages it touches passing their typecheck and tests is used. Several files are
  the same change written for different releases.

If no file of a folder fits a release, that run fails, GitHub notifies the owner, and no build
of that release appears until `patches/` changes. Earlier builds stay as they are.

## Changing what it carries

- **Carry another change**: add `patches/<upstream PR number or a name>/1-<name>.patch`, a
  `git diff` of the change against the release it is for. It may only change `apps/server` and
  `packages`: nothing else is rebuilt.
- **A change does not fit a new release**: add a second file to its folder with the change
  written for that release.
- **Stop carrying a change**: delete its folder. This is not needed once upstream ships a fix.

A change to `patches/` or `build.sh` makes the next run build the latest release again, as
build `n+1`. To build another release, run the workflow by hand with its tag.

## Branches

`t3kube` holds what makes the builds. The `fix/…` and `feat/…` branches are changes on
upstream's code, `pr-evidence` holds the screenshots that upstream's issues and pull requests
show, and `main` is where upstream's `main` was when the fork was made, and is not updated.
