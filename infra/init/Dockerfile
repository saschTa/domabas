FROM oven/bun:1.4.2-alpine@sha256:d888c0ae6c86d7866ff10c5aafdd9077b36aee6455b33dd270fb93c0dd5cef6f
WORKDIR /app
COPY infra/init/init.ts /app/init.ts
COPY LICENSE /usr/share/doc/domabas/LICENSE
COPY third_party/ /usr/share/doc/domabas/third-party/
USER bun
ENTRYPOINT ["bun", "--no-env-file", "/app/init.ts"]
