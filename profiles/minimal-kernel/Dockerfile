FROM node:22-bookworm-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392
RUN apt-get update -qq && apt-get install -y --no-install-recommends zip=3.0-13+deb12u1 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund && npm cache clean --force
COPY lib/ ./lib/
COPY vendor/ ./vendor/
COPY public/ ./public-build/
COPY sources.lock.json ./
USER 1000:1000
ENTRYPOINT ["node"]
CMD ["lib/host.js"]
