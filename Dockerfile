# syntax=docker/dockerfile:1
# rosboard — RouterOS 只读监控面板
# 多阶段构建: node(vite) → go(embed 前端) → alpine(运行时)
# 版本: 0.0.7

# ── 阶段 1: 前端构建 ──
# vite outDir 指向 ../internal/ui/dist, 产物必须落在 Go embed 目录
FROM node:22-alpine AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build
# 产物: /src/internal/ui/dist

# ── 阶段 2: Go 编译 ──
FROM golang:1.26.4-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
COPY --from=web /src/internal/ui/dist ./internal/ui/dist
# modernc.org/sqlite 纯 Go 实现, CGO_ENABLED=0 静态编译
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/rosboard ./cmd/rosboard

# ── 阶段 3: 运行时 ──
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata \
 && adduser -D -u 1000 rosboard
USER rosboard
WORKDIR /data
COPY --from=build /out/rosboard /usr/local/bin/rosboard
EXPOSE 8080
VOLUME ["/data"]
# 工作目录 /data: config.yaml(0600, 首存设备时自动创建) + ./data/ SQLite
ENTRYPOINT ["/usr/local/bin/rosboard"]
CMD ["-config", "/data/config.yaml"]
