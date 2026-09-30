FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS ocr-build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl cmake ninja-build g++ pkg-config libpng-dev libjpeg62-turbo-dev zlib1g-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl --fail --location --retry 3 --max-time 180 https://github.com/DanBloomberg/leptonica/releases/download/1.87.0/leptonica-1.87.0.tar.gz -o leptonica.tar.gz && \
    echo 'c73363397f96eb1295602bf44d708a994ad42046c791bf03ea0505d829bdb6a7  leptonica.tar.gz' | sha256sum --check && \
    mkdir leptonica && tar -xzf leptonica.tar.gz --strip-components=1 -C leptonica && \
    cmake -S leptonica -B lept-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_PROG=OFF -DENABLE_GIF=OFF -DENABLE_TIFF=OFF -DENABLE_WEBP=OFF -DENABLE_OPENJPEG=OFF && \
    cmake --build lept-build --parallel 2 && cmake --install lept-build
RUN curl --fail --location --retry 3 --max-time 180 https://codeload.github.com/tesseract-ocr/tesseract/tar.gz/db0ec62f81b0737fbbe184d8fea40af5738f8eef -o tesseract.tar.gz && \
    echo '21dbaff9867d937c156d0b898e90b726aa339129cfebd7e1365cd5fee5046d67  tesseract.tar.gz' | sha256sum --check && \
    mkdir tesseract && tar -xzf tesseract.tar.gz --strip-components=1 -C tesseract && \
    cmake -S tesseract -B tess-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TRAINING_TOOLS=OFF -DBUILD_TESTS=OFF -DOPENMP_BUILD=OFF -DDISABLE_TIFF=ON -DDISABLE_ARCHIVE=ON -DDISABLE_CURL=ON -DGRAPHICS_DISABLED=ON -DENABLE_NATIVE=OFF && \
    cmake --build tess-build --parallel 2 && cmake --install tess-build && \
    mkdir /notices && cp tesseract/LICENSE /notices/TESSERACT-LICENSE && cp leptonica/leptonica-license.txt /notices/LEPTONICA-LICENSE

FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS ocr-runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl libpng16-16t64 libjpeg62-turbo libstdc++6 zlib1g && rm -rf /var/lib/apt/lists/*
COPY --from=ocr-build /usr/local/bin/tesseract /usr/local/bin/tesseract
COPY --from=ocr-build /notices/ /usr/share/doc/domabas/ocr/
RUN tesseract --version && mkdir -p /models/tesseract /app/tmp && chmod 700 /app/tmp && chown -R 65532:65532 /models /app

FROM golang:1.27.1-trixie@sha256:9baa6b4187bbb98d240372a8a235ac0bb6b5ddd52bba1431dc2f7c0705862728 AS go-build
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/document-processor ./cmd/document-processor

FROM ocr-runtime
COPY --from=go-build /out/document-processor /app/document-processor
COPY LICENSE /usr/share/doc/domabas/LICENSE
COPY third_party/ /usr/share/doc/domabas/third-party/
WORKDIR /app
ENV HTTP_ADDR=0.0.0.0:8091 MODEL_CACHE_ROOT=/models/tesseract OLLAMA_CACHE_ROOT=/models/ollama/models OMP_THREAD_LIMIT=1 TMPDIR=/app/tmp
USER 65532:65532
EXPOSE 8091
ENTRYPOINT ["/app/document-processor"]
