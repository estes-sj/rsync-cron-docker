FROM alpine:latest

# Labels
LABEL org.opencontainers.image.title="rsync-cron" \
      org.opencontainers.image.description="Cron-based rsync runner with multi-source support, health checks, and optional event reporting." \
      org.opencontainers.image.url="https://hub.docker.com/r/estessj/rsync-cron" \
      org.opencontainers.image.source="https://github.com/estes-sj/rsync-cron-docker" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.authors="Samuel Estes <samuel.estes2000@gmail.com>"

# Install dependencies
RUN apk add --no-cache bash rsync curl tzdata python3 py3-pip jq coreutils

# Set up a virtual environment and install croniter
RUN python3 -m venv /venv && \
    . /venv/bin/activate && \
    pip install --no-cache-dir croniter

# Copy scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY run-rsync-jobs.sh /usr/local/bin/run-rsync-jobs.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/run-rsync-jobs.sh

# Set working dir
WORKDIR /data

# Ensure the virtualenv is used
ENV PATH="/venv/bin:$PATH"

# Cron runs in foreground
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
