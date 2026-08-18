# Node.js API image for the Regional Health service.
# Base pinned by digest (C5). CI builds omit mysql-client; local compose sets
# INSTALL_MYSQL_CLIENT=true for seed.sh.
FROM node:22-slim@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436

ARG INSTALL_MYSQL_CLIENT=false

# The seed script (local docker-compose only) needs the mysql CLI.
RUN if [ "$INSTALL_MYSQL_CLIENT" = "true" ]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends default-mysql-client bash \
      && rm -rf /var/lib/apt/lists/*; \
    fi

WORKDIR /usr/src/app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev \
    && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

COPY . .

# C5 image hardening: run as non-root (trivy DS-0002).
RUN groupadd -r appuser \
    && useradd -r -g appuser -d /usr/src/app appuser \
    && chown -R appuser:appuser /usr/src/app

EXPOSE 3000

USER appuser

CMD ["node", "server.js"]
