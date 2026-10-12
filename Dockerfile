# syntax=docker/dockerfile:1.7
# Один образ: FastAPI отдаёт и API (/api), и собранный Flutter web (/).

# ---------- 1. Сборка веб-клиента ----------
FROM debian:bookworm-slim AS web
ARG FLUTTER_VERSION=3.47.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m builder
USER builder
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /home/builder/flutter
ENV PATH="/home/builder/flutter/bin:${PATH}"
RUN flutter config --no-analytics >/dev/null && flutter precache --web
WORKDIR /home/builder/app
COPY --chown=builder app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY --chown=builder app/ ./
# CanvasKit — с нашего домена, а не с CDN: CSP разрешает только 'self'.
RUN flutter build web --release --no-web-resources-cdn

# ---------- 2. Бэкенд ----------
FROM python:3.14-slim AS app
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /srv/backend
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY backend/src ./src
RUN uv sync --locked --no-dev

COPY data/trips.json /srv/data/trips.json
COPY --from=web /home/builder/app/build/web /srv/web

RUN useradd --system --uid 10001 diary \
 && mkdir -p /var/lib/diary && chown diary /var/lib/diary
USER diary

ENV DIARY_ENV=prod \
    DIARY_HOST=0.0.0.0 \
    DIARY_PORT=8000 \
    DIARY_DB_PATH=/var/lib/diary/diary.db \
    DIARY_SEED_PATH=/srv/data/trips.json \
    DIARY_WEB_DIR=/srv/web \
    PATH="/srv/backend/.venv/bin:${PATH}"
EXPOSE 8000
VOLUME ["/var/lib/diary"]
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=2)"
CMD ["diary"]
