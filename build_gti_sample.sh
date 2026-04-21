#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${REPO_ROOT}/data"
CANONICAL_ROOT="${CANONICAL_ROOT:-/tmp/gdal-gti-sample}"
CANONICAL_DATA_DIR="${CANONICAL_ROOT}/data"

ensure_canonical_root() {
  local repo_real canonical_real

  repo_real="$(cd "${REPO_ROOT}" && pwd -P)"

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
    canonical_real="$(cd "${CANONICAL_ROOT}" && pwd -P)"
    if [ "${canonical_real}" = "${repo_real}" ]; then
      return
    fi
    echo "Refusing to reuse ${CANONICAL_ROOT}: path exists and is not this repo" >&2
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

build_masks() {
  local geojson="${DATA_DIR}/mask_star.geojson"
  local raw="${DATA_DIR}/.mask_star_raw.tif"

  echo "Generating ${geojson}"
  python3 - "${geojson}" <<'PY'
import json, math, sys
cx, cy = 1024.0, 1024.0
R_outer, R_inner = 800.0, 320.0
points = []
for k in range(10):
    theta = 2 * math.pi * k / 10
    rad = R_outer if k % 2 == 0 else R_inner
    points.append([cx + rad * math.sin(theta), cy + rad * math.cos(theta)])
points.append(points[0])
fc = {
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {"name": "star"},
            "geometry": {"type": "Polygon", "coordinates": [points]},
        }
    ],
}
with open(sys.argv[1], "w") as f:
    json.dump(fc, f, indent=2)
    f.write("\n")
PY

  rm -f "${raw}"
  gdal_rasterize -q -init 0 -burn 255 -ot Byte \
    -te 0 0 2048 2048 -ts 2048 2048 \
    -of GTiff \
    "${geojson}" "${raw}"

  for color in red green blue; do
    local main="${DATA_DIR}/${color}.tif"
    local msk="${main}.msk"

    echo "Building ${msk}"
    rm -f "${msk}" "${msk}.ovr" "${msk}.aux.xml"

    # Strip the WGS84 CRS + Y-up geotransform that gdal_rasterize
    # inherits from the GeoJSON, and emit the mask in the same bare
    # pixel space as red/green/blue.tif (no CRS, origin (0,0), Y-down)
    # so QGIS overlays the two layers on the same map extent.
    gdal_translate -q \
      -of GTiff \
      -a_srs "none" \
      -a_ullr 0 0 2048 2048 \
      -mo INTERNAL_MASK_FLAGS_1=2 \
      -mo INTERNAL_MASK_FLAGS_2=2 \
      -mo INTERNAL_MASK_FLAGS_3=2 \
      -co COMPRESS=DEFLATE \
      -co TILED=YES -co BLOCKXSIZE=512 -co BLOCKYSIZE=512 \
      "${raw}" "${msk}"

    gdaladdo -q -r nearest "${msk}" 2 4
    rm -f "${msk}.aux.xml"
  done

  rm -f "${raw}"
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

echo "Building z4_single.vrt"
gdalbuildvrt -overwrite \
  "${DATA_DIR}/z4_single.vrt" \
  "${DATA_DIR}/z4_0212.vrt" \
  "${DATA_DIR}/z4_0213.vrt"

echo "Building z4_single.tif"
gdal_translate -of GTiff \
  -co TILED=YES \
  -co COMPRESS=JPEG \
  -co INTERLEAVE=PIXEL \
  "${DATA_DIR}/z4_single.vrt" \
  "${DATA_DIR}/z4_single.tif"

echo "Building deep internal overviews for z4_single.tif"
gdaladdo -r nearest -minsize 1 \
  "${DATA_DIR}/z4_single.tif"

build_masks

cat <<EOF
Built GTI sample data:
  ${DATA_DIR}/z13_gti.gpkg
  ${DATA_DIR}/z8_gti.gpkg
  ${DATA_DIR}/z4_gti.gpkg
  ${DATA_DIR}/z4_single.vrt
  ${DATA_DIR}/z4_single.tif
  ${DATA_DIR}/mask_star.geojson
  ${DATA_DIR}/red.tif.msk
  ${DATA_DIR}/green.tif.msk
  ${DATA_DIR}/blue.tif.msk

Canonical absolute path root:
  ${CANONICAL_ROOT}
EOF
