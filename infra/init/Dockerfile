FROM temporalio/admin-tools:1.32.0@sha256:a9f84fb9a374b2374fe2e67c8efc0468ff3f1c66c8a0b14597ec86e349e62bca AS sql
FROM temporalio/temporal:1.9.1@sha256:ad4c82c97bd12b417d1ea942610dbcd511afb250c4d5ed26c694009533df447e AS cli
FROM oven/bun:1.4.2-alpine@sha256:d888c0ae6c86d7866ff10c5aafdd9077b36aee6455b33dd270fb93c0dd5cef6f
COPY --from=sql /usr/local/bin/temporal-sql-tool /usr/local/bin/temporal-sql-tool
COPY --from=sql /etc/temporal/schema /etc/temporal/schema
COPY --from=cli /usr/local/bin/temporal /usr/local/bin/temporal
WORKDIR /app
COPY infra/init/init.ts /app/init.ts
COPY LICENSE /usr/share/doc/domabas/LICENSE
COPY third_party/ /usr/share/doc/domabas/third-party/
USER bun
ENTRYPOINT ["bun", "--no-env-file", "/app/init.ts"]
