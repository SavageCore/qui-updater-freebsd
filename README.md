# qui & qBittorrent Updater for FreeBSD / TrueNAS Core

[![ShellCheck](https://github.com/SavageCore/qui-updater-freebsd/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/SavageCore/qui-updater-freebsd/actions/workflows/shellcheck.yml)

An automated update script for [qui](https://github.com/autobrr/qui) (qBittorrent web UI) and `qbittorrent-nox` on FreeBSD and TrueNAS Core systems.

## Features

- 🚀 Automatic download and installation of the latest qui release
- � Automatic updates for `qbittorrent-nox` via `pkg`
- �🔧 First-run setup: creates `quiuser`, installs services, and enables them
- 💾 Automatic backup of previous qui versions (keeps last 5)
- 🔄 Service management (stop/start during updates)
- ✅ Version checking to skip unnecessary updates

## Requirements

- FreeBSD or TrueNAS Core
- Root access
- Internet connectivity
- `screen` package installed (`pkg install screen`)

## Installation

### Quick Install

Download, save, and run the script in one command:

```sh
fetch -o /root/update_qui.sh https://raw.githubusercontent.com/SavageCore/qui-updater-freebsd/main/update_qui.sh && chmod +x /root/update_qui.sh && /root/update_qui.sh
```

### First Run

On first run, the script will automatically:

1. Install `qbittorrent-nox` and enable/start the service
2. Create the `quiuser` system user for qui
3. Install and enable the qui rc.d service script
4. Download and install the latest qui binary

## Accessing Services

Once installed, the services are available at your jail's IP address:

| Service | Port | Default URL | Default Credentials |
|---------|------|-------------|---------------------|
| **qui** | `7476` | `http://[jail-ip]:7476` | N/A (Configured in UI) |
| **qBittorrent** | `8080` | `http://[jail-ip]:8080` | `admin` / (See terminal output) |

> [!TIP]
> The script automatically patches `qui` to listen on all interfaces (`0.0.0.0`), ensuring it is accessible from your network.

## Configuration

The qui service supports several rc.conf variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `qui_enable` | `NO` | Enable/disable the service |
| `qui_user` | `quiuser` | User to run the service as |
| `qui_command` | `/usr/local/bin/qui serve` | Command to run |
| `qui_logfile` | `/home/quiuser/qui.log` | Log file location |
| `screen_name` | `qui` | Screen session name |

## Usage

### Update System

Simply run the script as root:

```sh
/root/update_qui.sh
```

The script will check both components and perform updates only if necessary.

### Service Management

```sh
# Management for qui
service qui start|stop|status

# Management for qBittorrent
service qbittorrent start|stop|status
```

### Attach to qui Screen Session

To view live qui output:

```sh
su - quiuser -c "screen -r qui"
# Detach with: Ctrl+A, then D
```

### Automatic Updates (Cron)

Add a cron job to check for updates daily at 3 AM:

```sh
(crontab -l 2>/dev/null; echo "0 3 * * * /root/update_qui.sh > /var/log/qui_update.log 2>&1") | crontab -
```

## File Locations

| Path | Description |
|------|-------------|
| `/usr/local/bin/qui` | qui binary |
| `/usr/local/etc/rc.d/qui` | qui service script |
| `/usr/local/etc/rc.d/qbittorrent` | qBittorrent service script |
| `/home/quiuser/` | qui home directory |
| `/home/quiuser/qui.log` | qui application log |
| `/root/qui_backups/` | qui backup directory |

## Troubleshooting

### Service won't start

Check that screen is installed:

```sh
pkg install screen
```

Check the log file:

```sh
tail -f /home/quiuser/qui.log
```

### Permission issues

Ensure the binary is owned by the correct user:

```sh
chown quiuser:quiuser /usr/local/bin/qui
chmod +x /usr/local/bin/qui
```

### Network issues

The script uses `fetch` to download from GitHub. Ensure you have internet connectivity:

```sh
fetch -o /dev/null https://api.github.com/repos/autobrr/qui/releases/latest
```

### Screen session issues

List all screen sessions for quiuser:

```sh
su - quiuser -c "screen -ls"
```

Kill a stuck screen session:

```sh
su - quiuser -c "screen -S qui -X quit"
```

## Development

### Pre-commit Hook

This project uses a Git pre-commit hook to run ShellCheck on all staged shell scripts. To set it up locally:

1.  **Install ShellCheck**:
    *   **Windows**: `choco install shellcheck` or `winget install shellcheck`
    *   **macOS**: `brew install shellcheck`
    *   **Linux**: Use your package manager (e.g., `sudo apt install shellcheck`)

2.  **Enable the Hook**:
    Run the following command to point Git to the version-controlled hook in this repository:
    ```bash
    git config core.hooksPath .githooks
    ```

## License

This project is released into the public domain under the [Unlicense](LICENSE).

## Credits

- [qui](https://github.com/autobrr/qui) - The qBittorrent web UI this script manages
- [autobrr](https://github.com/autobrr) - Maintainers of qui
