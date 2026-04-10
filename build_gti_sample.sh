#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${REPO_ROOT}/data"
CANONICAL_ROOT="${CANONICAL_ROOT:-/tmp/gdal-gti-sample}"
CANONICAL_DATA_DIR="${CANONICAL_ROOT}/data"

ensure_canonical_root() {
  if [ -L "${CANONICAL_ROOT}" ]; then
    local target
    target="$(readlink "${CANONICAL_ROOT}")"
    if [ "${target}" != "${REPO_ROOT}" ]; then
      echo "Refusing to reuse ${CANONICAL_ROOT}: symlink points to ${target}" >&2
      exit 1
    fi
    return
  fi

  if [ -e "${CANONICAL_ROOT}" ]; then
    echo "Refusing to reuse ${CANONICAL_ROOT}: path exists and is not a symlink" >&2
    exit 1
  fi

  ln -s "${REPO_ROOT}" "${CANONICAL_ROOT}"
}

build_index() {
  local output="$1"
  shift

  echo "Building ${output}"
  gdal driver gti create \
    --overwrite \
    --absolute-path \
    "$@" \
    "${DATA_DIR}/${output}"
}

ensure_canonical_root

# Equivalent classic syntax for one index:
# gdaltindex -overwrite -f GPKG -write_absolute_path data/z13_gti.gpkg /tmp/gdal-gti-sample/data/z13_*.vrt

build_index "z13_gti.gpkg" \
  --input "${CANONICAL_DATA_DIR}/z13_0212222222220.vrt" \
  --input "${CANONICAL_DATA_DIR}/z13_0212222222221.vrt" \
  --input "${CANONICAL_DATA_DIR}/z13_0212222222222.vrt" \
  --input "${CANONICAL_DATA_DIR}/z13_0212222222223.vrt"

build_index "z8_gti.gpkg" \
  --input "${CANONICAL_DATA_DIR}/z8_02122223.vrt" \
  --input "${CANONICAL_DATA_DIR}/z8_02132222.vrt"

build_index "z4_gti.gpkg" \
  --input "${CANONICAL_DATA_DIR}/z4_0212.vrt" \
  --input "${CANONICAL_DATA_DIR}/z4_0213.vrt"

cat <<EOF
Built GTI sample data:
  ${DATA_DIR}/z13_gti.gpkg
  ${DATA_DIR}/z8_gti.gpkg
  ${DATA_DIR}/z4_gti.gpkg

Canonical absolute path root:
  ${CANONICAL_ROOT}
EOF
