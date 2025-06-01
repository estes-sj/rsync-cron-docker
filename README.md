# Docker Rsync Cron Setup

A Dockerized solution for managing scheduled `rsync` jobs with `cron`. It supports multiple source-destination pairs, scheduling, optional health checks, and integration with [Backrest Summary Reporter](https://github.com/estes-sj/Backrest-Summary-Reporter) for event tracking.

## Features

* **Custom Schedule**: Cron scheduled `rsync` commands.
* **Multiple Pairs**: Configure as many source-destination storage pairs as needed (`STORAGE_FROM_1`/`STORAGE_TO_1`, etc.).
* **Healthcheck**: Ping [healthchecks](https://healthchecks.io/) for monitoring and notifications.
* **Reporting**: Send JSON job status data to [Backrest Summary Reporter](https://github.com/estes-sj/Backrest-Summary-Reporter).

## Getting Started

### Pre-requisites
- [Docker](https://docs.docker.com/engine/install/)
- [Backrest Summary Reporter](https://github.com/estes-sj/Backrest-Summary-Reporter) (optional - for event logging)

### Docker Compose

The [docker-compose.yaml](docker-compose.yaml) at the root of this project provides a standard setup that utilizes `rsync`.

To run this:
1. Create a new directory
2. Copy the [`.env.example`](.env.example) into a new `.env` file.
3. Modify the settings as needed (see [Environment Variables](#environment-variables)). At a minimum, configure the **Required** fields, which include the `rsync` `cron` schedule and at least one storage source-destination pair. Backrest Summary Reporter settings are defined [here](#backrest-summary-reporter-setup).
4. Run the container.
  ```bash
  docker compose up -d --build
  ```

You can test out a manual run with the following command to ensure it works smoothly:
```bash
docker exec rsync-cron /usr/local/bin/run-rsync-jobs.sh
```
See the container logs to see if it ran successfully.

### From Source
This repo also contains the source code used for building the `estessj/rsync-cron` image. It can be manually built and used by following these steps:

1. Clone the repository

   ```bash
   git clone https://github.com/estes-sj/rsync-cron-docker.git
   cd rsync-cron-docker
   ```

2. Copy and edit `.env`

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

   # Optional reporter endpoint (see the README section for more details)
   BACKREST_REPORTER_URL="https://example.com/report"
   ```

3. Build and run

   ```bash
   docker-compose up -d --build
   ```

4. View logs

   ```bash
   docker logs -f rsync-cron
   ```

### Environment Variables
Below are descriptions of the environment variables that can also be found at [`.env.example`](.env.example).

| Variable                    | Description                                                     | Required / Default |
| --------------------------- | --------------------------------------------------------------- | ------------------ |
| **SYNC\_FREQUENCY**         | Cron schedule in TZ format (e.g., `0 3 * * *` for 3 AM)         | Required           |
| **TZ**                      | Timezone for the application (e.g., `America/New_York`)         | Required           |
| **STORAGE\_FROM\_1**        | Host path for source of pair 1                                  | Required           |
| **STORAGE\_TO\_1**          | Host path for destination of pair 1                             | Required           |
| **STORAGE\_FROM\_2**        | Host path for source of pair 2                                  | Optional           |
| **STORAGE\_TO\_2**          | Host path for destination of pair 2                             | Optional           |
| **HEALTHCHECK\_PING\_URL**  | Healthcheck ping URL                                            | Optional           |
| **BACKREST\_REPORTER\_URL** | Backrest Summary Reporter endpoint URL                          | Optional           |
| **BACKREST\_API\_KEY**      | API key for Backrest Summary Reporter                           | Optional           |
| **STORAGE\_REPO\_1**        | Repo nickname for pair 1 (overrides default derived from paths) | Optional           |
| **STORAGE\_PLAN\_1**        | Plan nickname for pair 1 (overrides default derived from paths) | Optional           |
| **STORAGE\_REPO\_2**        | Repo nickname for pair 2 (overrides default derived from paths) | Optional           |
| **STORAGE\_PLAN\_2**        | Plan nickname for pair 2 (overrides default derived from paths) | Optional           |

## Backrest Summary Reporter Setup

The [Backrest Summary Reporter](https://github.com/estes-sj/Backrest-Summary-Reporter) stores snapshot events and creates configurable reports from them. The `rsync-cron` project can optionally create events that are compatible with the backrest summary reporter API.

1. Ensure `BACKREST_REPORTER_URL` and `BACKREST_API_KEY` are configured in your `.env`.
2. For each source-destination pair that is configured in your `.env` and `docker-compose.yaml`, you can optionally setup a `STORAGE_PLAN_N` and `STORAGE_REPO_N`, where `N` is the number of the source-destination pair. For example:
   ```bash
   STORAGE_FROM_1="/mnt/user_share"
   STORAGE_TO_1="/mnt-backup/samba/user_share"
   STORAGE_REPO_1="extdrive02-clone"
   STORAGE_PLAN_1="extdrive02-clone-usershare01"
   ```
3. Events will be automatically recorded in the API using the `REPO` and `PLAN` names. If the API is configured but no plan/repo names are provided, the `STORAGE_FROM_N` and `STORAGE_TO_N` values will be used instead.

### Example Full Setup with Backrest Summary Reporter

See [`docker-compose-backrest-reporter.yaml`](docker-examples/docker-compose-backrest-reporter.yaml) as a starting template for combining the two services.

More examples and additional details can be found in the [Backrest Summary Reporter](https://github.com/estes-sj/Backrest-Summary-Reporter) repository such as use of `rclone` mounts and the main `Backrest` service.


## Healthcheck and Reporting

If `HEALTHCHECK_PING_URL` is set, the `rsync-cron` service will regularly ping it during the following events:
- The start of the container
- A `/start` when initiating an `rsync` for each storage source-destination pair
- When the `rsync` completes for each storage source-destination pair
- A `/fail` if an `rsync` command fails
- A `/fail` if the Backrest Summary Reporter API is configured but fails when sending event data to

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.