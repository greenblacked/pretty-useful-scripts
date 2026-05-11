# syntax=docker/dockerfile:1.7
FROM python:3.12-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_ROOT_USER_ACTION=ignore

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /python

# Layer cache: deps first, source later.
COPY pyproject.toml ./
COPY src ./src
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && pip install -e ".[dev]"

COPY tests ./tests

# Default command is overridden by docker-compose.yml for the dev service
# (which keeps the container alive). One-shot `docker compose run` defaults
# to pytest.
CMD ["pytest", "-q"]
