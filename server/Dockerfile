# Build context is this directory (server/), not the repo root — the lobby shares
# nothing with the Godot game but the repository it lives in.
FROM golang:1-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# The test page is embedded in the binary (see main.go's //go:embed), so the
# runtime image is one file plus a healthcheck.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/lobby .

FROM alpine:3.22
RUN apk add --no-cache wget ca-certificates && \
    addgroup -g 1000 lobby && \
    adduser -D -u 1000 -G lobby lobby
COPY --from=build /out/lobby /usr/local/bin/lobby
USER lobby
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["/usr/local/bin/lobby"]
