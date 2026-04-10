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

## Build The GTI GeoPackages

Run the checked-in build script from the repo root:

```bash
./build_gti_sample.sh
```

This creates:

- `data/z13_gti.gpkg`
- `data/z8_gti.gpkg`
- `data/z4_gti.gpkg`

The script uses `gdal driver gti create --absolute-path` and pins all tile paths to a canonical absolute root at `/tmp/gdal-gti-sample`. It creates a symlink from that path to the repo so the generated GeoPackages can be committed with stable absolute paths and then reopened inside Docker by mounting the repo at the same location.

Equivalent classic GDAL tooling is:

```bash
gdaltindex -overwrite -f GPKG -write_absolute_path data/z13_gti.gpkg /tmp/gdal-gti-sample/data/z13_*.vrt
gdaltindex -overwrite -f GPKG -write_absolute_path data/z8_gti.gpkg /tmp/gdal-gti-sample/data/z8_*.vrt
gdaltindex -overwrite -f GPKG -write_absolute_path data/z4_gti.gpkg /tmp/gdal-gti-sample/data/z4_*.vrt
```

## Use In Docker

This repo documents and verifies the sample against the official GDAL docker image. Mount this repo at the same canonical path used inside the committed XML and GeoPackages:

```bash
docker run --rm -it \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  ghcr.io/osgeo/gdal:ubuntu-full-3.12.2 \
  gdalinfo data/sample_gti.xml
```

## Render 256x256 PNG Samples

These examples force different overview levels while keeping the output images at 256x256:

```bash
docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  ghcr.io/osgeo/gdal:ubuntu-full-3.12.2 \
  gdal_translate -of PNG -ovr NONE -srcwin 0 0 256 256 -outsize 256 256 \
  data/sample_gti.xml /tmp/gdal-gti-sample/red_z13.png

docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  ghcr.io/osgeo/gdal:ubuntu-full-3.12.2 \
  gdal_translate -of PNG -ovr 4 -srcwin 0 0 256 256 -outsize 256 256 \
  data/sample_gti.xml /tmp/gdal-gti-sample/green_z8.png

docker run --rm \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  ghcr.io/osgeo/gdal:ubuntu-full-3.12.2 \
  gdal_translate -of PNG -ovr 5 -srcwin 0 0 256 256 -outsize 256 256 \
  data/sample_gti.xml /tmp/gdal-gti-sample/blue_z4.png
```

Expected results:

- `red_z13.png` renders from the full-resolution z13 tiles.
- `green_z8.png` renders from the GTI overview dataset backed by `z8_gti.gpkg`.
- `blue_z4.png` renders from the farthest concrete overview exposed by the chained GTI XML, backed by `z4_gti.gpkg`.

## Verify Source Overview Reuse

When the source tile is backed by data with internal overviews, GDAL GTI can still reuse those source overviews rather than delegating to other levels.

For the first reduced-resolution copy of the full-resolution mosaic, `-ovr 0` means:

- start from the z13 GTI layer,
- request its first GTI overview level, which is `4096x4096 -> 2048x2048`,
- then render a `256x256` output from that request.

That is an 8x reduction relative to the underlying `2048x2048` z13 tile, so the best internal match in `red.tif` is its `512x512` overview.

Run this exact proof step in Docker:

```bash
docker run --rm \
  -e CPL_DEBUG=GTiff,VRT,GTI \
  -v "$PWD":/tmp/gdal-gti-sample \
  -w /tmp/gdal-gti-sample \
  ghcr.io/osgeo/gdal:ubuntu-full-3.12.2 \
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
