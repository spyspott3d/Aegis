#!/usr/bin/env bash
# scripts/release.sh
# Tags a release and pushes the tag. The GitHub Action (.github/workflows/release.yml)
# builds the zip and creates the GitHub Release automatically.
#
# Usage:
#   bash scripts/release.sh 1.0.0
#   bash scripts/release.sh 1.0.1
#   bash scripts/release.sh 1.1.0

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash scripts/release.sh <version>"
  echo "Example: bash scripts/release.sh 1.0.0"
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
TOC="Aegis/Aegis.toc"

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]]; then
  echo "[release] Version must be semver: MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-prerelease"
  exit 1
fi

if [ ! -f "${TOC}" ]; then
  echo "[release] ${TOC} not found. Run from repo root."
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "[release] Working tree is not clean. Commit or stash first."
  git status --short
  exit 1
fi

if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "[release] Tag ${TAG} already exists."
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "${CURRENT_BRANCH}" != "main" ]; then
  echo "[release] Releases must be cut from main. You are on ${CURRENT_BRANCH}."
  exit 1
fi

echo "[release] Updating ${TOC} Version field to ${VERSION}..."
sed "s/^## Version: .*/## Version: ${VERSION}/" "${TOC}" > "${TOC}.tmp"
mv "${TOC}.tmp" "${TOC}"

if ! grep -q "^## Version: ${VERSION}$" "${TOC}"; then
  echo "[release] Failed to update version in ${TOC}. Inspect the file."
  exit 1
fi

git add "${TOC}"
# Skip the commit when the .toc was already at the target version (first
# release, or re-running the script after a manual bump). Without this,
# `git commit` aborts on "nothing to commit" and `set -e` kills the script
# before the tag is created.
git diff --cached --quiet || git commit -m "release: ${VERSION}"
git tag -a "${TAG}" -m "Release ${VERSION}"

echo "[release] Pushing main and tag ${TAG}..."
git push origin main
git push origin "${TAG}"

echo ""
echo "[release] Done."
echo "Watch: https://github.com/spyspott3d/Aegis/actions"
