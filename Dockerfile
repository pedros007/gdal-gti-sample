FROM debian:trixie-slim

ARG GDAL_COMMIT=de74003daf79aa943ad4a0cd3b349b9815edc78f

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
    && mkdir -p /tmp/gdal-src \
    && curl -fsSL "https://github.com/OSGeo/gdal/archive/${GDAL_COMMIT}.tar.gz" \
        | tar -xzf - --strip-components=1 -C /tmp/gdal-src \
    && mkdir -p /tmp/gdal-src/build \
    && cd /tmp/gdal-src/build \
    && cmake .. \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && gdalinfo --version \
    && psql --version \
    && rm -rf /tmp/gdal-src \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
