# Node.js API image for the Regional Health service.
FROM node:22-slim

# The seed script (run inside this container) needs the mysql CLI.
RUN apt-get update \
    && apt-get install -y --no-install-recommends default-mysql-client bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

COPY package.json ./
RUN npm install --omit=dev

COPY . .

# C5 image hardening: run as non-root (trivy DS-0002). npm install stays root;
# chown before switching user so the app can read node_modules at runtime.
RUN groupadd -r appuser \
    && useradd -r -g appuser -d /usr/src/app appuser \
    && chown -R appuser:appuser /usr/src/app

# The seed script lives in ../data-seed and is bind-mounted at runtime by
# docker-compose to /usr/local/bin/seed.sh (it is outside this build context,
# so it cannot be COPYed here).

EXPOSE 3000

USER appuser

CMD ["node", "server.js"]
