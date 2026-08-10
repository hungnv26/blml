# BLML chat server.
#
# Built from the rebranded source in ../server, NOT from an upstream release
# tarball. Upstream's own Dockerfile does `ADD .../tinode-$DB.linux-amd64.tar.gz`,
# which would (a) ship stock Tinode branding, ignoring our rebranded email
# templates, and (b) pull an amd64-only binary that needs emulation on Apple
# Silicon. Building from source fixes both and lets us patch the server later.
#
# Build context is the repo root (../), so this can reach both server/ and webapp/.
#   docker compose build

# ---------- stage 1: compile the server ----------
FROM golang:1.26-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /src

# Dependencies first so edits to our source don't invalidate the module cache.
COPY server/go.mod server/go.sum ./
RUN go mod download

COPY server/ ./

# The postgres adapter is behind a build tag (`//go:build postgres`).
# Adding more tags here also compiles those adapters into the binary.
RUN CGO_ENABLED=0 go build -tags postgres -ldflags="-s -w" -o /out/blml-server ./server && \
    CGO_ENABLED=0 go build -tags postgres -ldflags="-s -w" -o /out/init-db     ./tinode-db && \
    CGO_ENABLED=0 go build              -ldflags="-s -w" -o /out/keygen       ./keygen

# ---------- stage 2: runtime ----------
FROM alpine:3.22

# ca-certificates is required for the email validator to talk to TLS SMTP servers.
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /opt/blml

COPY --from=builder /out/blml-server /out/init-db /out/keygen ./

# Email/SMS templates. Paths in the config are relative to this working
# directory ("./templ/email-validation-{{.Language}}.templ"), and these carry
# the BLML rebranding.
COPY server/server/templ ./templ

# NOTE: deliberately NOT copying server/tinode-db/data.json. That is upstream's
# sample dataset (alice/bob/carol with published passwords). init-db only loads
# it when passed --data, but shipping it at all invites an accident.

# The built web app, served at "/" via static_mount.
COPY webapp/index.html webapp/privacy.html webapp/manifest.json webapp/service-worker.js \
     webapp/version.js webapp/firebase-init.js ./static/
COPY webapp/umd   ./static/umd
COPY webapp/css   ./static/css
COPY webapp/img   ./static/img
COPY webapp/audio ./static/audio

# Uploaded files land here; mount a volume over it so they survive redeploys.
RUN mkdir -p /var/blml/uploads

EXPOSE 6060

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD wget -q -O- http://localhost:6060/ >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/opt/blml/blml-server"]
CMD ["--config=/etc/blml/blml.conf", "--static_data=/opt/blml/static"]
