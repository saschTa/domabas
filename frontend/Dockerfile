FROM --platform=linux/amd64 debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils libglu1-mesa && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.47.4
ARG FLUTTER_SHA256=5b45f0ceda99b9bebdc873e7e69f6450aeb4c30f454b505e2e62fc9255a907d3
RUN curl --fail --location --retry 3 "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz && \
    echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum --check && \
    tar -xJf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" CI=true
WORKDIR /src
COPY frontend/ ./
RUN flutter pub get --enforce-lockfile && flutter build web --release --no-web-resources-cdn

FROM nginx:1.30.5-alpine@sha256:25820c39dba41369486df729ad6697de2fab631ca809e0503e1d1e0c73d9a232
COPY infra/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
COPY LICENSE /usr/share/doc/domabas/LICENSE
COPY third_party/ /usr/share/doc/domabas/third-party/
EXPOSE 8080
