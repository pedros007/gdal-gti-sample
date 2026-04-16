FROM debian:trixie-slim

ARG GDAL_VERSION=3.12.3

WORKDIR /tmp/gdal-gti-sample

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        libgeos-dev \
        libjpeg-dev \
        libpng-dev \
        libproj-dev \
        libsqlite3-dev \
        libtiff-dev \
        pkg-config \
        postgresql-client \
        zlib1g-dev \
    && curl -fsSL "https://download.osgeo.org/gdal/${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz" \
        | tar -xzf - -C /tmp \
    && mkdir -p "/tmp/gdal-${GDAL_VERSION}/build" \
    && cd "/tmp/gdal-${GDAL_VERSION}/build" \
    && cmake .. \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && gdalinfo --version \
    && psql --version \
    && rm -rf "/tmp/gdal-${GDAL_VERSION}" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
