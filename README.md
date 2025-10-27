# Workflow OCR Backend

![Build Action](https://github.com/R0Wi-DEV/workflow_ocr_backend/actions/workflows/test.yml/badge.svg)

This is an alternative backend for the [workflow_ocr](https://github.com/R0Wi-DEV/workflow_ocr) Nextcloud App.
It's written in Python and provides a simple REST API for [ocrmypdf](https://ocrmypdf.readthedocs.io/en/latest/).

- [Workflow OCR Backend](#workflow-ocr-backend)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [`docker-compose` Example](#docker-compose-example)
  - [HaRP Support (Nextcloud 32+)](#harp-support-nextcloud-32)

## Prerequisites

This app should be installed via Nextcloud [ExApp / AppApi](https://docs.nextcloud.com/server/latest/admin_manual/exapps_management/AppAPIAndExternalApps.html).
It will take care of all the heavy lifting like installation, orchestration, configuration and authentication between Nextcloud and this backend implementation.

1. Install [`docker`](https://docs.docker.com/engine/install/ubuntu/) on the host where the app should be installed.
2. Install the [`AppApi`](https://docs.nextcloud.com/server/latest/admin_manual/exapps_management/AppAPIAndExternalApps.html#installing-appapi) app. It will take care of the installation and orchestration of the backend as Docker Container.
3. Setup a [Deploy Daemon](https://docs.nextcloud.com/server/latest/admin_manual/exapps_management/AppAPIAndExternalApps.html#setup-deploy-daemon):
   - **For Nextcloud 32+**: It's recommended to use [HaRP (AppAPI HaProxy Reversed Proxy)](https://github.com/nextcloud/HaRP) for better performance and simplified deployment.
   - **For older versions**: Use the [Docker Socket Proxy](https://github.com/nextcloud/docker-socket-proxy#readme) to communicate with the docker daemon.

## Installation

The easiest way to install this app is to use the [Nexcloud Appstore](https://apps.nextcloud.com/apps/workflow_ocr_backend). You can find more information about how to install ExApps [here](https://docs.nextcloud.com/server/latest/admin_manual/exapps_management/AppAPIAndExternalApps.html#installing-exapps).

Alternatively, use the folling [`occ`](https://docs.nextcloud.com/server/latest/admin_manual/occ_command.html) command to register the latest version of this app:

```bash
sudo -u www-data php occ app_api:app:register workflow_ocr_backend \
	--info-xml https://raw.githubusercontent.com/R0Wi-DEV/workflow_ocr_backend/refs/heads/master/appinfo/info.xml
```

Use `sudo -u www-data php occ app_api --help` to get a full list of AppApi commands.

## `docker-compose` Example

If you want to run both Nextcloud **and** this backend in Docker, you can use the following `docker-compose.yml` to start Nextcloud, a database and the docker-socket-proxy. 

**(1)** Create a new docker network first:

```bash
docker network create nextcloud
```

**(2)** Then create a `docker-compose.yml` file with the following content:

```yaml
volumes:
  nextcloud:
  db:

networks:
  nextcloud:
    name: nextcloud
    external: true

services:
  db:
    image: mariadb:10.6
    restart: no
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    volumes:
      - db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=
      - MYSQL_PASSWORD=
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MARIADB_ROOT_PASSWORD=nextcloud
    networks:
      - nextcloud

  app:
    image: nextcloud:<version>
    container_name: nextcloud-in-docker
    restart: no
    ports:
      - 80:80
    volumes:
      - nextcloud:/var/www/html
    environment:
      - MYSQL_PASSWORD=
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_HOST=db
      - PHP_MEMORY_LIMIT=1024M
      - PHP_UPLOAD_LIMIT=1024M
    networks:
      - nextcloud

  nextcloud-cron:
    image: nextcloud:<version>
    container_name: nextcloud-in-docker-cron
    restart: no
    volumes:
      - nextcloud:/var/www/html
    entrypoint: /cron.sh
    depends_on:
      - app
    networks:
      - nextcloud
    environment:
      - PHP_MEMORY_LIMIT=1024M
      - PHP_UPLOAD_LIMIT=1024M

  # Proxy for Docker Socket
  nextcloud-appapi-dsp:
    image: ghcr.io/nextcloud/nextcloud-appapi-dsp:release
    container_name: docker-socket-proxy
    hostname: nextcloud-appapi-dsp
    environment:
      - NC_HAPROXY_PASSWORD=password
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: no
    privileged: true
    networks:
      - nextcloud
```

Adjust the values for `<version>` and `NC_HAPROXY_PASSWORD` to your needs, then start the stack with `docker-compose up -d`.

**(3)** Before configuring the Deploy Daemon, make sure to add the Docker network DNS name (`nextcloud-in-docker`) of the Nextcloud container to the `trusted_domains` in `config/config.php`:

```php
<?php
$CONFIG = array (
    // ...
    'trusted_domains' => 
        array (
          0 => 'localhost',
          1 => 'nextcloud-in-docker'
        )
)
```

Otherwise, ExApps might not be able to connect back to your Nextcloud instance and fail with errors like this:

```bash
# Taken from "docker logs <nc-ex-app-container-id>
File "/home/serviceuser/.local/lib/python3.12/site-packages/anyio/_backends/_asyncio.py", line 2461, in run_sync_in_worker_thread
    return await future
           ^^^^^^^^^^^^
  File "/home/serviceuser/.local/lib/python3.12/site-packages/anyio/_backends/_asyncio.py", line 962, in run
    result = context.run(func, *args)
             ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/serviceuser/.local/lib/python3.12/site-packages/nc_py_api/ex_app/integration_fastapi.py", line 138, in fetch_models_task
    nc.set_init_status(100)
  File "/home/serviceuser/.local/lib/python3.12/site-packages/nc_py_api/nextcloud.py", line 431, in set_init_status
    self._session.ocs(
  File "/home/serviceuser/.local/lib/python3.12/site-packages/nc_py_api/_session.py", line 213, in ocs
    check_error(response, info)
  File "/home/serviceuser/.local/lib/python3.12/site-packages/nc_py_api/_exceptions.py", line 65, in check_error
    raise NextcloudException(status_code, reason=codes(status_code).phrase, info=info)
nc_py_api._exceptions.NextcloudException: [400] Bad Request <request: PUT /ocs/v1.php/apps/app_api/apps/status/workflow_ocr_backend>

```

**(4)** The Deploy Daemon configuration for this setup would look like this:

<p align="center">
    <img src="./doc/img/deploy-daemon.png" width="30%"/>
</p>

>  :warning: Make sure to create the docker network `nextcloud` before starting the stack. If you don't declare the network as
> `external`, `docker-compose` will create the network with some [project/directory prefix](https://docs.docker.com/compose/how-tos/networking/), which will cause the Deploy Daemon to fail because it doesn't find the network.

## HaRP Support (Nextcloud 32+)

Since Nextcloud 32, [HaRP (AppAPI HaProxy Reversed Proxy)](https://github.com/nextcloud/HaRP) is the recommended deployment method for ExApps. This app now supports HaRP out of the box.

### What is HaRP?

HaRP is a reverse proxy system that simplifies the deployment workflow for Nextcloud's AppAPI. It enables direct communication between clients and ExApps, bypassing the Nextcloud instance to improve performance and reduce complexity compared to the Docker Socket Proxy (DSP) setup.

### Key Benefits

- **Simplified Deployment**: Replaces more complex setups with an easy-to-use container
- **Better Performance**: Routes requests directly to ExApps
- **Enhanced Security**: Uses brute-force protection and basic authentication
- **Flexible**: Supports both HTTP and HTTPS for ExApps and Nextcloud control

### Installation

Follow the [HaRP installation guide](https://github.com/nextcloud/HaRP#how-to-install-it) to deploy HaRP on your system. Once HaRP is running, you can install this ExApp through the Nextcloud AppStore or via the `occ` command as described in the [Installation](#installation) section.

### Migration from Docker Socket Proxy

If you're upgrading to Nextcloud 32 and want to migrate from DSP to HaRP:

1. Install HaRP on the same Docker Engine that you were using for DSP
2. Test deployment on HaRP using the usual "TestDeploy" button
3. Set HaRP as the default deployment daemon for ExApps
4. Remove the ExApp **without** deleting its data volumes:
   - From terminal: Do not use the `--rm-data` option
   - From UI: Do not check "Delete data when removing"
5. Reinstall the ExApp - it will now use HaRP
6. Remove DSP once all ExApps have been migrated

For more details, see the [HaRP migration guide](https://github.com/nextcloud/HaRP#nextcloud-32-migrating-existing-exapps-from-dsp-to-harp).
