FROM alpine:latest

# Install dependencies
RUN apk add --no-cache bash rsync curl tzdata python3 py3-pip

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
