# Docker Rsync Cron Setup

This repository provides a Docker-based solution for scheduling and running `rsync` jobs using `cron`. It supports multiple source-destination pairs, customizable scheduling, optional healthchecks, and sending event data to [Backrest Summary Reporter](https://github.com/estes-sj/Backrest-Summary-Reporter).

## Features

* **Custom Schedule**: Define the cron schedule via `SYNC_FREQUENCY` in `.env`.
* **Multiple Pairs**: Configure up to N storage pairs (`STORAGE_FROM_1`/`STORAGE_TO_1`, etc.).
* **Healthcheck**: Optionally ping a URL after each run with `HEALTHCHECK_PING_URL`.
* **Reporting**: Send JSON job status data to `BACKREST_REPORTER_URL`.

## Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/estes-sj/rsync-cron-docker.git
   cd rsync-cron-docker
   ```

2. **Copy and edit `.env`**

   ```bash
   cp .env.example .env
   ```

   Edit `.env` to set your schedule and storage paths:

   ```dotenv
   # Cron schedule ("min hour day month weekday")
   SYNC_FREQUENCY="0 3 * * *"

   # Storage pair 1
   STORAGE_FROM_1="/host/source1"
   STORAGE_TO_1="/host/dest1"

   # Storage pair 2 (optional)
   STORAGE_FROM_2="/host/source2"
   STORAGE_TO_2="/host/dest2"

   # Timezone
   TZ="America/New_York"

   # Optional healthcheck URL
   HEALTHCHECK_PING_URL="https://example.com/health"

   # Optional reporter endpoint
   BACKREST_REPORTER_URL="https://example.com/report"
   ```

3. **Build and run**

   ```bash
   docker-compose up -d --build
   ```

4. **View logs**

   ```bash
   docker logs -f rsync-cron
   ```

## Customizing

* **Additional rsync options**: Edit `run-rsync-jobs.sh` template in `entrypoint.sh`.
* **Logging**: Logs are written to `/var/log/rsync-cron.log` inside the container.
* **Scaling**: For many pairs, add corresponding volumes in `docker-compose.yml`.

## Healthcheck & Reporting

* If `HEALTHCHECK_PING_URL` is set, Docker’s `HEALTHCHECK` will call it every minute.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.