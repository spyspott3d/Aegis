#!/usr/bin/env bash
# package.sh
# Build the distributable zip for Aegis.
#
# The zip contains ONLY the Aegis/ addon folder. No markdown, no
# scripts, no screenshots, no .github, no internal docs. Exactly what an end
# user drops into Interface/AddOns/.

set -euo pipefail

ADDON_DIR="Aegis"
TOC="${ADDON_DIR}/Aegis.toc"

if [ ! -f "${TOC}" ]; then
  echo "[package] ${TOC} not found. Run from repo root."
  exit 1
fi

VERSION=$(grep "^## Version:" "${TOC}" | awk '{print $3}')
if [ -z "${VERSION}" ]; then
  echo "[package] Could not read version from ${TOC}. Expected line '## Version: X.Y.Z'."
  exit 1
fi

ZIP_NAME="Aegis.zip"

rm -f "${ZIP_NAME}"

zip -r "${ZIP_NAME}" "${ADDON_DIR}" \
  -x "${ADDON_DIR}/.*" \
  -x "${ADDON_DIR}/**/.*" \
  -x "${ADDON_DIR}/**/*.bak" \
  -x "${ADDON_DIR}/**/*.lua~" \
  -x "${ADDON_DIR}/**/Thumbs.db" \
  -x "${ADDON_DIR}/**/.DS_Store" \
  > /dev/null

echo "[package] Built ${ZIP_NAME} (version ${VERSION})"
unzip -l "${ZIP_NAME}" | head -n 20
