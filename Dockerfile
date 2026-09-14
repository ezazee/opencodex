# syntax=docker/dockerfile:1

ARG BUN_IMAGE=oven/bun:1.4.2@sha256:9114c058aeae42162ee16dd5084b95fe9473970bb6bcb5b232ab1630f0546895


FROM ${BUN_IMAGE} AS build

USER root

RUN apt-get update \
    && apt-get install -y git \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /home/bun/app


COPY docker/verify-compatibility.ts /tmp/verify-compatibility.ts


COPY --chown=bun:bun package.json bun.lock tsconfig.json ./


RUN bun install --frozen-lockfile


# Needed by generate-compatibility-version.ts
COPY --chown=bun:bun scripts ./scripts

# Needed because generator uses git ls-files
COPY --chown=bun:bun .git ./.git


RUN bun scripts/generate-compatibility-version.ts



COPY --chown=bun:bun gui/package.json gui/bun.lock ./gui/


RUN cd gui && bun install --frozen-lockfile



COPY --chown=bun:bun src ./src
COPY --chown=bun:bun docker ./docker
COPY --chown=bun:bun gui ./gui



RUN cd gui && bun run build





FROM ${BUN_IMAGE} AS runtime


WORKDIR /home/bun/app



ENV NODE_ENV=production \
    OCX_SERVICE=1 \
    OPENCODEX_HOME=/home/bun/.opencodex \
    CODEX_HOME=/home/bun/.codex \
    OCX_API_TOKEN_FILE=/home/bun/.opencodex/service-api-token



RUN install -d -m 0700 -o bun -g bun \
    /home/bun/.opencodex \
    /home/bun/.codex



COPY --chown=bun:bun --chmod=0600 \
    docker/config.json \
    /home/bun/.opencodex/config.json



COPY --from=build --chown=bun:bun \
    /home/bun/app/package.json \
    ./package.json


COPY --from=build --chown=bun:bun \
    /home/bun/app/bun.lock \
    ./bun.lock


COPY --from=build --chown=bun:bun \
    /home/bun/app/node_modules \
    ./node_modules



COPY --from=build --chown=bun:bun \
    /home/bun/app/src \
    ./src



COPY --from=build --chown=bun:bun \
    /home/bun/app/scripts \
    ./scripts



COPY --from=build --chown=bun:bun \
    /home/bun/app/docker \
    ./docker



COPY --from=build --chown=bun:bun \
    /home/bun/app/gui/dist \
    ./gui/dist



USER bun



RUN bun docker/verify-compatibility.ts


RUN bun -e "import { readOpenCodexCompatibilityVersion } from './src/routing/compatibility/version.ts'; if (!/^[0-9a-f]{64}$/.test(readOpenCodexCompatibilityVersion() ?? '')) throw new Error('Missing or invalid generated compatibility manifest');"



VOLUME ["/home/bun/.opencodex", "/home/bun/.codex"]



EXPOSE 10100



HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD bun -e "const r=await fetch('http://127.0.0.1:10100/healthz');if(!r.ok)process.exit(1)"



CMD ["bun", "run", "src/cli/index.ts", "start", "--port", "10100"]
