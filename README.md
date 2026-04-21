# gdal-gti-sample

This repo demonstrates some of the features of the [GDAL Raster Tile Index (GTI) driver](https://gdal.org/en/stable/drivers/raster/gti.html). In particular:

- GDAL can build GeoPackage tile indexes  which happen to adhere to GTI
- GTI XML can chain overviews to other GTI datasets, including "overviews of overviews".
- GDAL can resolve reads to either internal GTiff overviews or external "overviews of overviews" specified as a different GTI

The `data/` directory stores a few things:

- JPEG-compressed COGs `red.tif`, `green.tif` and `blue.tif` in EPSG:4326.
- VRTs use the COGs to align with a https://github.com/DigitalGlobe/tiletanic quadtree in the DGTiling schema:
  - zoom 13 VRTs point to red imagery representing 2.385m pixels (full resolution).
  - zoom 8 VRTs point to green imagery representing 4.77m pixels
  - zoom 4 VRTs point to blue imagery representing 9.54m pixels
- `sample_gti.xml` is a GTI XML demonstrating how overview delegation
  works: zoomed-in requests render red, intermediate requests render
  green, and far-out requests render blue.  z13 inline overviews are
  used for factors `2, 4, 8, 16` and GTI-backed overview datasets for
  z8 (`32, 64, 128`) and z4 (`256, 512, 1024`).
- `sample_gti_z4_single.xml` demonstrates the same GTI structure with a
  single full-extent z4 image, `z4_single.tif`, instead of a z4
  GeoPackage GTI. The single-image branch is built with a deep internal
  overview pyramid and, with recent GDAL fixes, now follows the same
  red / green / blue progression as `sample_gti.xml`.

## Build The GTI GeoPackages

Run the checked-in build script from the repo root:

```bash
./build_gti_sample.sh
```

This creates:

- `data/z13_gti.gpkg`
- `data/z8_gti.gpkg`
- `data/z4_gti.gpkg`
- `data/z4_single.vrt`
- `data/z4_single.tif`

The script uses `gdal driver gti create --absolute-path` and pins all tile paths to a canonical absolute root at `/tmp/gdal-gti-sample`. It creates a symlink from that path to the repo so the generated GeoPackages can be committed with stable absolute paths and then reopened inside Docker by mounting the repo at the same location.

Equivalent classic GDAL tooling is:

```bash
gdaltindex -overwrite -f GPKG -write_absolute_path data/z13_gti.gpkg /tmp/gdal-gti-sample/data/z13_*.vrt
gdaltindex -overwrite -f GPKG -write_absolute_path data/z8_gti.gpkg /tmp/gdal-gti-sample/data/z8_*.vrt
gdaltindex -overwrite -f GPKG -write_absolute_path data/z4_gti.gpkg /tmp/gdal-gti-sample/data/z4_*.vrt
gdal_create -of GTiff -outsize 4096 4096 -bands 3 -burn 254 -burn 0 -burn 0 \
  -co TILED=YES -co COMPRESS=JPEG -co INTERLEAVE=PIXEL data/red.tif
gdal_create -of GTiff -outsize 4096 4096 -bands 3 -burn 0 -burn 255 -burn 1 \
  -co TILED=YES -co COMPRESS=JPEG -co INTERLEAVE=PIXEL data/green.tif
gdal_create -of GTiff -outsize 4096 4096 -bands 3 -burn 0 -burn 0 -burn 254 \
  -co TILED=YES -co COMPRESS=JPEG -co INTERLEAVE=PIXEL data/blue.tif
gdaladdo -r nearest -minsize 1 data/red.tif
gdaladdo -r nearest -minsize 1 data/green.tif
gdaladdo -r nearest -minsize 1 data/blue.tif
gdalbuildvrt -overwrite data/z4_single.vrt data/z4_0212.vrt data/z4_0213.vrt
gdal_translate -of GTiff -co TILED=YES -co COMPRESS=JPEG -co INTERLEAVE=PIXEL \
  data/z4_single.vrt data/z4_single.tif
gdaladdo -r nearest -minsize 1 data/z4_single.tif
```

## Build And Use In Docker

Build the local Docker image from this repo's `Dockerfile`. The
examples below use GDAL commit `4bf06c5`, which as of this writing
corresponds to `v3.13.0 beta`:

```bash
docker build --build-arg GDAL_COMMIT=4bf06c5 --progress plain -t gdal-gti-sample:4bf06c5 .
```

Then mount this repo at the same canonical path used inside the
committed XML and GeoPackages:

```bash
docker run --rm -it \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdalinfo data/sample_gti.xml
```

## Render Red, Green, And Blue Samples

These examples use the locally built Docker image and exercise requests
that select the red, green, and blue branches from `sample_gti.xml`:

```bash
docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdal_translate -of PNG -srcwin 0 0 4096 4096 -outsize 4096 4096 \
  data/sample_gti.xml red_z13.png

docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdal_translate -of PNG -srcwin 0 0 65536 65536 -outsize 1024 1024 \
  data/sample_gti.xml green_z8.png

docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdal_translate -of PNG -srcwin 0 0 65535 65535 -outsize 4 4 \
  data/sample_gti.xml blue_z4.png
```

Expected results:

- `red_z13.png` renders from the full-resolution z13 tiles.
- `green_z8.png` renders from the delegated green `z8_gti.gpkg` branch.
- `blue_z4.png` renders from the delegated blue `z4_gti.gpkg` branch.

## Verify Source Overview Reuse

When the source tile is backed by data with internal overviews, GDAL GTI can still reuse those source overviews rather than delegating to other levels.

For the first reduced-resolution copy of the full-resolution mosaic, `-ovr 0` means:

- start from the z13 GTI layer,
- request its first GTI overview level, which is `8192x8192 -> 4096x4096`,
- then render a `256x256` output from that request.

That is a 16x reduction relative to the underlying `4096x4096` z13 tile,
so the best internal match in `red.tif` is one of its internal
overviews, not the full-resolution source data.

Run this exact proof step in Docker:

```bash
docker run --rm \
  -e CPL_DEBUG=GTiff,VRT,GTI \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdal_translate -of PNG -ovr 0 -srcwin 0 0 256 256 -outsize 256 256 \
  data/sample_gti.xml /vsimem/ovr0.png
```

Expected debug lines include:

```text
GTiff: ScanDirectories()
GTiff: Opened 1024x1024 overview.
GTiff: Opened 512x512 overview.
```

That output shows the GTI read path opening the internal overviews from `red.tif` while serving the first reduced-resolution GTI request. In other words, the sample is demonstrating both:

- GTI-level overview selection through `sample_gti.xml`
- reuse of lower-level GeoTIFF overviews when the selected source data already has them

## Single-Image z4 Variant

`data/sample_gti_z4_single.xml` is an alternate GTI XML that keeps the
same red full-resolution base but uses:

- z13 inline overviews for the first reduced-resolution levels
- `z8_gti.gpkg` for the first delegated green overview level
- `z4_single.tif` for the coarse single-image branch

This variant is intentionally simpler than `sample_gti.xml`: it is meant
to demonstrate that the coarse branch can be a single raster image
instead of a z4 GeoPackage GTI. With recent GDAL fixes, it now reaches
the same red / green / blue progression as the GeoPackage-backed
`sample_gti.xml`.

- `data/z4_single.vrt` mosaics `z4_0212.vrt` and `z4_0213.vrt`
- `data/z4_single.tif` stores the single merged z4 image as a tiled
  GeoTIFF with a deliberately deep internal overview pyramid built by
  `gdaladdo -minsize 1`
- the coarse single-image branch still uses the same blue source data

Inspect it with:

```bash
gdalinfo data/sample_gti_z4_single.xml
```

To render the same three branch-selection probes against the
single-image variant, use:

```bash
docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdal_translate -of PNG -srcwin 0 0 4096 4096 -outsize 4096 4096 \
  data/sample_gti_z4_single.xml z4_single_red.png

docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdal_translate -of PNG -srcwin 0 0 65536 65536 -outsize 1024 1024 \
  data/sample_gti_z4_single.xml z4_single_green.png

docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  gdal-gti-sample:4bf06c5 \
  gdal_translate -of PNG -srcwin 0 0 65535 65535 -outsize 4 4 \
  data/sample_gti_z4_single.xml z4_single_blue.png
```
