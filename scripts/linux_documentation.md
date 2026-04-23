# 🐧 Linux Commands & Shell Scripting — Complete Interview Q&A

> A comprehensive guide covering Linux commands and shell scripting concepts with detailed explanations, real-world examples, and interview tips.

---

## 📋 Table of Contents

- [Part 1 — Linux Commands](#part-1--linux-commands)
- [Part 2 — Advanced Linux Commands](#part-2--advanced-linux-commands)
- [Part 3 — Shell Scripting Basics](#part-3--shell-scripting-basics)
- [Part 4 — Advanced Shell Scripting](#part-4--advanced-shell-scripting)
- [Part 5 — Linux Directory Structure](#part-5--linux-directory-structure)
- [Part 6 — Linux Boot Process](#part-6--linux-boot-process)
- [Part 7 — System Administration](#part-7--system-administration)
- [Part 8 — DevOps-Focused Linux](#part-8--devops-focused-linux)
- [Part 9 — Practical Shell Script Examples](#part-9--practical-shell-script-examples)
- [Quick Reference Cheatsheet](#quick-reference-cheatsheet)

---

# Part 1 — Linux Commands

## 1️⃣ What is the difference between `ls`, `ls -l`, and `ls -a`?

These are all variations of the **list directory contents** command, each revealing different levels of detail.

| Command | Description |
|---------|-------------|
| `ls` | Lists files in current directory (names only) |
| `ls -l` | Long listing format — shows permissions, ownership, size, modified time |
| `ls -a` | Shows **all** files including hidden ones (files starting with `.`) |
| `ls -la` | Combines both: long format + hidden files |
| `ls -lh` | Long format with human-readable file sizes (KB, MB, GB) |
| `ls -lt` | Long format sorted by modification time (newest first) |

### Example output of `ls -l`:

```bash
$ ls -l
-rwxr-xr-- 1 hitesh devops 4096 Jun 10 09:30 script.sh
drwxr-xr-x 2 hitesh devops 4096 Jun 09 14:00 projects
```

Reading the columns left to right:
1. `-rwxr-xr--` → File type + permissions
2. `1` → Number of hard links
3. `hitesh` → Owner name
4. `devops` → Group name
5. `4096` → File size in bytes
6. `Jun 10 09:30` → Last modification timestamp
7. `script.sh` → File name

### Example: Show all files including hidden:

```bash
$ ls -a
.  ..  .bashrc  .profile  script.sh  projects
```

`.bashrc` and `.profile` are **hidden config files** — they start with a dot (`.`).

---

## 2️⃣ What does `chmod` do?

`chmod` stands for **Change Mode**. It modifies the **read, write, and execute permissions** for files and directories.

### Permission Bits Explained:

| Symbol | Octal | Meaning |
|--------|-------|---------|
| `r` | 4 | Read |
| `w` | 2 | Write |
| `x` | 1 | Execute |
| `-` | 0 | No permission |

### Octal Permission Examples:

| Octal | Symbolic | Meaning |
|-------|----------|---------|
| `755` | `rwxr-xr-x` | Owner: full, Group+Others: read+execute |
| `644` | `rw-r--r--` | Owner: read+write, Group+Others: read only |
| `700` | `rwx------` | Owner: full, Group+Others: no access |
| `777` | `rwxrwxrwx` | Everyone: full access (avoid in production!) |

### Usage Examples:

```bash
# Numeric method
chmod 755 script.sh       # Owner: rwx, Group: r-x, Others: r-x
chmod 644 config.txt      # Owner: rw-, Group: r--, Others: r--
chmod 700 private.sh      # Only owner can read, write, execute

# Symbolic method
chmod u+x script.sh       # Add execute for owner (user)
chmod g-w file.txt        # Remove write from group
chmod o+r file.txt        # Add read for others
chmod a+x script.sh       # Add execute for all (a = all)
chmod u=rwx,g=rx,o=r file # Set exact permissions

# Recursive (apply to directory and all contents)
chmod -R 755 /var/www/html
```

> 💡 **Interview Tip**: Always explain that `755` is common for scripts/directories, and `644` is standard for regular files.

---

## 3️⃣ How to view the first and last lines of a file?

### `head` — View beginning of a file:

```bash
head filename.txt          # Shows first 10 lines (default)
head -n 20 filename.txt    # Shows first 20 lines
head -5 filename.txt       # Shows first 5 lines
```

### `tail` — View end of a file:

```bash
tail filename.txt          # Shows last 10 lines (default)
tail -n 20 filename.txt    # Shows last 20 lines
tail -f /var/log/syslog    # Follow mode: real-time log monitoring
tail -F /var/log/app.log   # Follow mode + retry if file is recreated
```

### Practical use case — Monitor logs in real time:

```bash
# Watch nginx access log live
tail -f /var/log/nginx/access.log

# Watch last 50 lines + follow
tail -n 50 -f /var/log/syslog

# Combine head and tail to view middle of file
# View lines 20-30 of a file:
head -30 file.txt | tail -11
```

---

## 4️⃣ How to search a string in files using `grep`?

`grep` stands for **Global Regular Expression Print**. It searches for patterns in files or input.

### Basic Syntax:

```bash
grep "pattern" filename
grep "pattern" file1 file2     # Search in multiple files
grep "pattern" *.log           # Search in all .log files
```

### Important Flags:

| Flag | Description |
|------|-------------|
| `-i` | Case-insensitive search |
| `-r` | Recursive search in directories |
| `-n` | Show line numbers |
| `-v` | Invert match (show lines NOT matching) |
| `-c` | Count matching lines |
| `-l` | Show only filenames with matches |
| `-w` | Match whole words only |
| `-A n` | Show n lines After match |
| `-B n` | Show n lines Before match |
| `-E` | Extended regex (same as `egrep`) |

### Examples:

```bash
grep "error" /var/log/syslog             # Find errors in syslog
grep -i "error" app.log                  # Case-insensitive
grep -r "TODO" /home/hitesh/projects/    # Recursive search
grep -n "function" script.sh             # Show line numbers
grep -v "DEBUG" app.log                  # Exclude DEBUG lines
grep -c "404" access.log                 # Count 404 occurrences
grep -w "fail" logs.txt                  # Whole word match only
grep -A 3 "ERROR" app.log               # Show 3 lines after each match
grep -E "error|warning|critical" app.log # Extended regex with OR

# Chain with pipes (real-world usage)
ps -ef | grep nginx                      # Find nginx process
cat /etc/passwd | grep hitesh            # Find user in passwd file
```

---

## 5️⃣ What does `df -h` show?

`df` stands for **Disk Free**. It reports disk space usage of filesystems.

```bash
df -h       # Human-readable (KB, MB, GB)
df -H       # Same but uses 1000 instead of 1024
df -T       # Show filesystem type
df -i       # Show inode usage instead of space
df -hT      # Combine: human-readable + filesystem type
```

### Example output:

```bash
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        50G   20G   30G  40% /
tmpfs           1.9G     0  1.9G   0% /dev/shm
/dev/sdb1       100G   80G   20G  80% /data
```

Reading the columns:
- **Filesystem** — Device or partition
- **Size** — Total size
- **Used** — Space used
- **Avail** — Available space
- **Use%** — Percentage used
- **Mounted on** — Where it is accessible

> 💡 **Pro Tip**: When `Use%` hits 90%+ on `/` (root), your system may start having issues. This is commonly checked in disk alert scripts.

---

## 6️⃣ What is the difference between `ps` and `top`?

Both commands deal with **process monitoring**, but serve different purposes.

| Feature | `ps` | `top` |
|---------|------|-------|
| View type | Static snapshot | Dynamic real-time |
| Auto-refresh | No | Yes (every 3 seconds) |
| Interactive | No | Yes (press keys to interact) |
| Use case | Quick one-time check | Ongoing monitoring |

### `ps` — Process Snapshot:

```bash
ps              # Processes in current shell
ps -e           # All processes on system
ps -ef          # Full format: UID, PID, PPID, CPU, start time
ps -ef | grep nginx    # Find specific process
ps aux          # BSD format: user, CPU%, MEM%, command
ps aux --sort=-%cpu    # Sort by CPU usage (descending)
ps aux --sort=-%mem    # Sort by memory usage
```

### Example output of `ps -ef`:

```
UID        PID  PPID  C STIME TTY          TIME CMD
root         1     0  0 09:01 ?        00:00:03 /sbin/init
hitesh    1234  1200  0 09:05 pts/0    00:00:00 bash
```

### `top` — Interactive Process Monitor:

```bash
top             # Launch top
# While inside top:
# q = quit
# k = kill a process (enter PID)
# M = sort by memory
# P = sort by CPU
# u = filter by user
# 1 = show per-CPU stats
```

> 💡 **Alternative**: `htop` is a more user-friendly, colored version of `top`. Install with: `apt install htop`

---

## 7️⃣ What is `sudo`?

`sudo` stands for **Superuser Do**. It allows a permitted user to run commands as **root (administrator)** without fully switching to the root account.

### Why use `sudo` instead of logging in as root?

- Safer — limits damage from mistakes
- Auditable — all `sudo` commands are logged in `/var/log/auth.log`
- Granular — you can control which commands each user can run

### Examples:

```bash
sudo apt update               # Update package list (requires root)
sudo systemctl restart nginx  # Restart service
sudo nano /etc/hosts          # Edit protected system file
sudo -i                       # Switch to root shell (interactive)
sudo -u postgres psql         # Run command as specific user (postgres)
sudo !!                       # Re-run last command with sudo
```

### How to grant sudo access:

```bash
# Add user to sudo group (Ubuntu/Debian)
usermod -aG sudo hitesh

# Add user to wheel group (RHEL/CentOS)
usermod -aG wheel hitesh
```

### Check sudo privileges:

```bash
sudo -l          # List what the current user can run with sudo
```

---

## 8️⃣ How do you check system logs?

Linux stores logs in `/var/log/` directory. Different services write to different files.

### Common Log Files:

| Log File | Purpose |
|----------|---------|
| `/var/log/syslog` | General system messages (Debian/Ubuntu) |
| `/var/log/messages` | General system messages (RHEL/CentOS) |
| `/var/log/auth.log` | Authentication, SSH logins, sudo usage |
| `/var/log/kern.log` | Kernel messages |
| `/var/log/dmesg` | Hardware detection at boot |
| `/var/log/nginx/access.log` | Nginx web server access |
| `/var/log/nginx/error.log` | Nginx errors |
| `/var/log/dpkg.log` | Package install/remove history (Debian) |

### Commands:

```bash
tail -f /var/log/syslog           # Follow real-time
tail -100 /var/log/auth.log       # Last 100 lines
grep "Failed" /var/log/auth.log   # Find failed SSH attempts
cat /var/log/syslog | less        # Scroll through logs
dmesg                             # Kernel ring buffer (boot messages)
dmesg | grep -i error             # Kernel errors
journalctl                        # systemd journal (all logs)
journalctl -u nginx               # Logs for specific service
journalctl -f                     # Follow mode (like tail -f)
journalctl --since "2024-01-01"   # Logs since a date
journalctl -p err                 # Only error-level and above
```

---

## 9️⃣ What is the difference between soft link and hard link?

Both are ways to **reference a file**, but they work very differently under the hood.

| Feature | Soft Link (Symbolic) | Hard Link |
|---------|---------------------|-----------|
| Points to | File **name/path** | File **inode** (actual data) |
| Breaks if original deleted | ✅ Yes (dangling link) | ❌ No (data persists) |
| Can link directories | ✅ Yes | ❌ No |
| Cross filesystem links | ✅ Yes | ❌ No |
| Shows as separate file type | ✅ `l` in `ls -l` | ❌ Appears identical |
| File size shown | Size of path string | Size of actual file |

### Create links:

```bash
ln -s /path/to/original link_name     # Create soft link
ln /path/to/original link_name        # Create hard link

# Examples
ln -s /var/www/html /home/hitesh/www   # Soft link to directory
ln -s /usr/bin/python3 /usr/bin/python # Alias command
ln important.txt backup_link.txt       # Hard link to file
```

### View links:

```bash
ls -l        # Soft links show: link_name -> /original/path
ls -li       # Shows inode numbers (hard links share same inode)
readlink -f link_name   # Show absolute path of soft link target
```

### Soft link example:

```bash
$ ln -s /var/log/syslog mysyslog
$ ls -l mysyslog
lrwxrwxrwx 1 hitesh hitesh 15 Jun 10 10:00 mysyslog -> /var/log/syslog
```

---

## 🔟 How to find files in Linux?

The `find` command is a powerful tool to search for files based on various criteria.

### Basic Syntax:

```bash
find [path] [options] [expression]
```

### Common Examples:

```bash
# Find by name
find / -name "file.txt"               # Find anywhere on system
find /home -name "*.sh"               # Find all shell scripts
find /var -name "*.log"               # Find all log files
find . -name "config*"                # Find files starting with config

# Find by type
find /tmp -type f                     # Files only
find /home -type d                    # Directories only
find / -type l                        # Symbolic links only

# Find by size
find /var -size +10M                  # Files larger than 10MB
find /home -size -1k                  # Files smaller than 1KB
find / -size +100M -size -1G         # Between 100MB and 1GB

# Find by time
find /tmp -mtime -1                   # Modified in last 24 hours
find /logs -mtime +30                 # Not modified in 30+ days
find /home -newer reference.txt       # Newer than a specific file

# Find by permissions
find / -perm 777                      # Files with 777 permissions
find / -perm -u=s                     # SUID files (security audit)

# Find by owner
find /home -user hitesh               # Files owned by hitesh
find /var -group www-data             # Files owned by group www-data

# Execute action on found files
find /tmp -name "*.tmp" -delete       # Delete all .tmp files
find /logs -name "*.log" -exec cat {} \;   # Cat each found file
find /home -type f -exec chmod 644 {} \;  # Fix permissions
```

---

# Part 2 — Advanced Linux Commands

## 1️⃣ What is the difference between `cron` and `at` commands?

Both schedule tasks, but for different use cases.

| Feature | `cron` | `at` |
|---------|--------|------|
| Purpose | Recurring/scheduled tasks | One-time future tasks |
| Config file | `/etc/crontab`, `/var/spool/cron/` | No config file |
| Frequency | Runs repeatedly on schedule | Runs once at specified time |
| Persistence | Survives reboots | Runs once and is done |
| Use case | Backups, cleanups, monitoring | One-off maintenance task |

### Cron Syntax:

```
* * * * * command_to_execute
| | | | |
| | | | └── Day of week (0=Sun, 6=Sat)
| | | └──── Month (1-12)
| | └────── Day of month (1-31)
| └──────── Hour (0-23)
└────────── Minute (0-59)
```

### Cron Examples:

```bash
crontab -e    # Edit current user's cron jobs
crontab -l    # List current user's cron jobs
crontab -r    # Remove all cron jobs

# Common cron schedules:
0 1 * * *      /home/user/backup.sh     # Daily at 1:00 AM
*/5 * * * *    /usr/bin/monitor.sh      # Every 5 minutes
0 0 * * 0      /scripts/weekly.sh       # Every Sunday midnight
0 9-17 * * 1-5 /scripts/workday.sh     # 9AM-5PM Mon-Fri (hourly)
@reboot        /scripts/startup.sh      # Run at boot
@daily         /scripts/daily.sh        # Alias for 0 0 * * *
```

### `at` Command:

```bash
at 10:30 PM          # Schedule for 10:30 PM tonight
at 2:00 AM tomorrow  # Tomorrow at 2 AM
at now + 1 hour      # One hour from now
at 09:00 06/15/2024  # Specific date and time

# Usage (interactive)
$ at 10:30 PM
at> echo "Hello" > /tmp/test.txt
at> <Ctrl+D>

atq    # List pending at jobs
atrm 3 # Remove job number 3
```

---

## 2️⃣ Explain file permissions in symbolic format

### Reading Permission String:

```
-rwxr-xr--
 |||||||||||
 |└──┘└──┘└──┘
 |  |   |   └── Others (world): r--  = 4
 |  |   └────── Group:          r-x  = 5
 |  └────────── Owner (user):   rwx  = 7
 └───────────── File type: - (file), d (dir), l (link), c (char), b (block)
```

### File Type Characters:

| Character | Meaning |
|-----------|---------|
| `-` | Regular file |
| `d` | Directory |
| `l` | Symbolic link |
| `c` | Character device |
| `b` | Block device |
| `p` | Named pipe |
| `s` | Socket |

### Special Permissions:

```bash
# SUID (Set User ID) — runs as file owner, not current user
chmod u+s /usr/bin/passwd
# Shows as: -rwsr-xr-x

# SGID (Set Group ID) — files inherit group of directory
chmod g+s /shared/folder
# Shows as: drwxr-sr-x

# Sticky Bit — only owner can delete their own files
chmod +t /tmp
# Shows as: drwxrwxrwt
```

---

## 3️⃣ How to check network connectivity?

```bash
# Basic connectivity test
ping google.com             # Send ICMP packets continuously
ping -c 4 google.com        # Send only 4 packets
ping -i 2 google.com        # Interval 2 seconds between pings

# IP configuration
ip addr show                # Show all network interfaces and IPs
ip addr show eth0           # Show specific interface
ifconfig                    # Older alternative (may need net-tools)

# Routing
ip route show               # Show routing table
route -n                    # Show routing table (numeric)
traceroute google.com       # Show packet path to destination
tracepath google.com        # Similar to traceroute

# Port and connection monitoring
ss -tulnp                   # Show listening ports (modern)
netstat -tulnp              # Show listening ports (older)
ss -s                       # Summary statistics
ss -tp                      # TCP connections with process names

# DNS lookup
nslookup google.com         # DNS query
dig google.com              # Detailed DNS query
host google.com             # Simple DNS lookup
cat /etc/resolv.conf        # View configured DNS servers

# Network interface statistics
ip -s link show eth0        # Packet statistics
```

---

## 4️⃣ What is `tar` used for?

`tar` stands for **Tape Archive**. It bundles multiple files into a single archive (and optionally compresses it).

### Flags Explained:

| Flag | Meaning |
|------|---------|
| `-c` | Create archive |
| `-x` | Extract archive |
| `-v` | Verbose (show progress) |
| `-f` | Specify filename |
| `-z` | Compress with gzip (.gz) |
| `-j` | Compress with bzip2 (.bz2) |
| `-J` | Compress with xz (.xz) |
| `-t` | List contents without extracting |
| `-C` | Extract to specific directory |

### Examples:

```bash
# Create archives
tar -cvf backup.tar /home/user           # Plain archive
tar -czvf backup.tar.gz /home/user       # Gzip compressed
tar -cjvf backup.tar.bz2 /home/user      # Bzip2 (smaller, slower)

# Extract archives
tar -xvf backup.tar                      # Extract in current dir
tar -xzvf backup.tar.gz                  # Extract gzip archive
tar -xvf backup.tar -C /tmp/restore/     # Extract to specific dir

# View contents without extracting
tar -tvf backup.tar.gz

# Append to existing archive
tar -rvf backup.tar newfile.txt

# Extract specific file from archive
tar -xvf backup.tar home/user/file.txt
```

---

## 5️⃣ Difference between `apt` and `yum`/`dnf`?

These are **package managers** — tools that install, update, and remove software on Linux.

| Feature | `apt` | `yum` / `dnf` |
|---------|-------|---------------|
| Distribution | Debian, Ubuntu | RHEL, CentOS, Fedora |
| Package format | `.deb` | `.rpm` |
| Package repos | APT repositories | YUM/DNF repositories |
| Config location | `/etc/apt/` | `/etc/yum.repos.d/` |
| Cache location | `/var/cache/apt/` | `/var/cache/yum/` |

### `apt` Commands (Ubuntu/Debian):

```bash
apt update                    # Refresh package list
apt upgrade                   # Upgrade all installed packages
apt install nginx             # Install package
apt remove nginx              # Remove package (keep config)
apt purge nginx               # Remove package + config files
apt search "web server"       # Search for packages
apt show nginx                # Show package details
apt list --installed          # List installed packages
apt autoremove                # Remove unused dependencies
```

### `yum`/`dnf` Commands (RHEL/CentOS/Fedora):

```bash
yum update                    # Update all packages
yum install nginx             # Install package
yum remove nginx              # Remove package
yum search nginx              # Search packages
yum info nginx                # Package details
dnf install nginx             # dnf is modern replacement for yum
```

---

## 6️⃣ What is `du` command used for?

`du` stands for **Disk Usage**. It shows how much space files and directories consume.

```bash
du -sh /var/log          # Human-readable size of /var/log
du -sh *                 # Size of each item in current directory
du -h --max-depth=1 /    # Size of top-level dirs in root
du -h /home | sort -rh   # Sort dirs by size (largest first)
du -ah /etc              # All files and dirs with sizes
du -sh /var/log/*.log    # Size of individual log files

# Practical: Find top 10 largest directories
du -h /home | sort -rh | head -10
```

---

## 7️⃣ What is SELinux?

**Security-Enhanced Linux (SELinux)** is a mandatory access control (MAC) security framework built into the Linux kernel — primarily used in RHEL/CentOS systems.

Traditional Linux uses **Discretionary Access Control (DAC)** — owner decides permissions. SELinux adds **Mandatory Access Control (MAC)** — system policy controls access regardless of owner.

### SELinux Modes:

| Mode | Behavior |
|------|----------|
| `enforcing` | Actively blocks and logs policy violations |
| `permissive` | Only logs violations (does NOT block) — used for debugging |
| `disabled` | SELinux completely off |

### Commands:

```bash
getenforce              # Check current mode
sestatus                # Full SELinux status
setenforce 0            # Temporarily set to permissive (until reboot)
setenforce 1            # Temporarily set to enforcing

# Permanent change: edit /etc/selinux/config
SELINUX=enforcing       # Options: enforcing, permissive, disabled

# Check SELinux context of file
ls -Z /var/www/html/index.html

# Fix file context (common fix for web servers)
restorecon -Rv /var/www/html/

# View SELinux denials in audit log
grep "denied" /var/log/audit/audit.log
```

---

## 8️⃣ How to check system resource usage?

```bash
# CPU and processes
top                      # Interactive process monitor
htop                     # Enhanced version of top
vmstat 1                 # Virtual memory stats every 1 second
vmstat -s                # Summary memory stats
mpstat                   # Per-CPU statistics
uptime                   # Load average overview

# Memory
free -m                  # Memory in megabytes
free -h                  # Human-readable
cat /proc/meminfo        # Detailed memory information

# Disk I/O
iostat                   # I/O stats for disks
iostat -x 1              # Extended stats every 1 second
iotop                    # Real-time disk I/O per process

# CPU info
lscpu                    # CPU architecture details
cat /proc/cpuinfo        # Raw CPU information
nproc                    # Number of processing units

# Network I/O
iftop                    # Real-time network bandwidth by connection
nethogs                  # Network usage per process
```

---

# Part 3 — Shell Scripting Basics

## 1️⃣ What is a shell script?

A **shell script** is a plain text file containing a series of Linux/Unix commands that are executed sequentially by the shell interpreter (like `bash`, `sh`, `zsh`).

### Why use shell scripts?

- **Automate repetitive tasks** — backups, deployments, cleanups
- **Batch processing** — process multiple files at once
- **System administration** — user management, monitoring
- **DevOps pipelines** — CI/CD automation, infrastructure tasks

### Structure of a basic shell script:

```bash
#!/bin/bash
# This is a comment
# Script: hello.sh
# Purpose: Basic shell script example
# Author: Hitesh
# Date: 2024-06-10

# Variables
NAME="Hitesh"
DATE=$(date +%Y-%m-%d)

# Main logic
echo "Hello, $NAME!"
echo "Today is: $DATE"
echo "Script completed successfully."
```

### How to run a script:

```bash
# Method 1: Make executable and run
chmod +x hello.sh
./hello.sh

# Method 2: Run with bash directly
bash hello.sh

# Method 3: Source (run in current shell)
source hello.sh
. hello.sh    # Shorthand for source
```

---

## 2️⃣ How to define and access variables?

Variables store data that can be reused throughout the script.

### Variable Rules:

- No spaces around `=` sign
- Variable names are case-sensitive (`NAME` ≠ `name`)
- Convention: use UPPERCASE for constants, lowercase for regular vars

```bash
#!/bin/bash

# Assign variables (no spaces around =)
name="Hitesh"
age=25
city="Mumbai"

# Access variables with $
echo "Name: $name"
echo "Age: $age"
echo "City: $city"

# Curly braces (recommended for clarity)
echo "Hello, ${name}!"

# Command substitution (store command output in variable)
current_date=$(date +%Y-%m-%d)
current_user=$(whoami)
file_count=$(ls | wc -l)

echo "Date: $current_date"
echo "User: $current_user"
echo "Files in current dir: $file_count"

# Read-only variables (constants)
readonly MAX_RETRIES=3
readonly APP_NAME="MyApp"

# Unset a variable
unset age
echo "Age: $age"    # Will print nothing

# Default values
echo ${undefined_var:-"default value"}   # Use default if unset
echo ${name:="Anonymous"}               # Assign default if unset
```

### Special Variables:

```bash
$HOME        # Current user's home directory
$PATH        # List of directories to search for commands
$USER        # Current username
$HOSTNAME    # Machine hostname
$SHELL       # Current shell
$PWD         # Current working directory
$RANDOM      # Random number
$LINENO      # Current line number in script
$$           # PID of current shell/script
$!           # PID of last background process
```

---

## 3️⃣ What are positional parameters?

Positional parameters allow passing **arguments to a script** from the command line.

```bash
./script.sh arg1 arg2 arg3
```

### Special Parameter Variables:

| Variable | Meaning |
|----------|---------|
| `$0` | Name of the script |
| `$1` | First argument |
| `$2` | Second argument |
| `$n` | nth argument |
| `$#` | Number of arguments passed |
| `$@` | All arguments as separate words |
| `$*` | All arguments as one string |
| `$?` | Exit status of last command |
| `$$` | PID of current script |

### Example script using positional parameters:

```bash
#!/bin/bash
# Usage: ./greet.sh Hitesh Mumbai

echo "Script name: $0"
echo "First arg: $1"
echo "Second arg: $2"
echo "Total args: $#"
echo "All args: $@"

# Real-world example: deploy.sh
if [ $# -lt 2 ]; then
    echo "Usage: $0 <environment> <version>"
    echo "Example: $0 production 1.2.3"
    exit 1
fi

ENVIRONMENT=$1
VERSION=$2
echo "Deploying version $VERSION to $ENVIRONMENT..."
```

```bash
$ ./deploy.sh production 1.2.3
Deploying version 1.2.3 to production...

$ ./deploy.sh
Usage: ./deploy.sh <environment> <version>
Example: ./deploy.sh production 1.2.3
```

---

## 4️⃣ How do you write an `if` condition in bash?

### Syntax:

```bash
if [ condition ]; then
    # code if true
elif [ condition ]; then
    # code if elif is true
else
    # code if all above false
fi
```

### Numeric Comparison Operators:

| Operator | Meaning |
|----------|---------|
| `-eq` | Equal to |
| `-ne` | Not equal to |
| `-gt` | Greater than |
| `-lt` | Less than |
| `-ge` | Greater than or equal |
| `-le` | Less than or equal |

### String Comparison Operators:

| Operator | Meaning |
|----------|---------|
| `==` or `=` | String equal |
| `!=` | String not equal |
| `-z` | String is empty |
| `-n` | String is not empty |

### File Test Operators:

| Operator | Meaning |
|----------|---------|
| `-f` | File exists and is a regular file |
| `-d` | Directory exists |
| `-e` | File/directory exists |
| `-r` | File is readable |
| `-w` | File is writable |
| `-x` | File is executable |
| `-s` | File exists and is not empty |

### Examples:

```bash
#!/bin/bash

# Numeric comparison
num=15
if [ $num -gt 10 ]; then
    echo "$num is greater than 10"
fi

# String comparison
env="production"
if [ "$env" == "production" ]; then
    echo "WARNING: Running in production!"
elif [ "$env" == "staging" ]; then
    echo "Running in staging"
else
    echo "Running in development"
fi

# File check
config_file="/etc/nginx/nginx.conf"
if [ -f "$config_file" ]; then
    echo "Nginx config found"
elif [ ! -f "$config_file" ]; then
    echo "Nginx config NOT found!"
fi

# Multiple conditions
age=25
city="Mumbai"
if [ $age -gt 18 ] && [ "$city" == "Mumbai" ]; then
    echo "Adult from Mumbai"
fi

if [ "$env" == "production" ] || [ "$env" == "staging" ]; then
    echo "Running in a live environment"
fi

# Using [[ ]] (bash extended test — more features)
if [[ $name =~ ^[A-Z] ]]; then
    echo "Name starts with uppercase"
fi
```

---

## 5️⃣ How to use loops?

### `for` loop — iterate over list or range:

```bash
#!/bin/bash

# Loop over a list
for fruit in apple banana mango orange; do
    echo "Fruit: $fruit"
done

# Loop over a range
for i in {1..10}; do
    echo "Number: $i"
done

# Loop with step
for i in {0..20..5}; do
    echo "Step: $i"
done

# C-style for loop
for ((i=1; i<=5; i++)); do
    echo "Count: $i"
done

# Loop over files
for file in /var/log/*.log; do
    echo "Processing: $file"
    wc -l "$file"
done

# Loop over command output
for user in $(cat /etc/passwd | cut -d: -f1); do
    echo "User: $user"
done
```

### `while` loop — repeat while condition is true:

```bash
#!/bin/bash

# Basic while loop
count=1
while [ $count -le 5 ]; do
    echo "Count: $count"
    count=$((count + 1))
done

# Read file line by line
while IFS= read -r line; do
    echo "Line: $line"
done < /etc/hosts

# Infinite loop with break
while true; do
    echo "Checking service..."
    if systemctl is-active --quiet nginx; then
        echo "nginx is running!"
        break
    fi
    sleep 5
done

# Until loop (opposite of while — runs until condition is TRUE)
until [ -f /tmp/done.flag ]; do
    echo "Waiting for task to complete..."
    sleep 2
done
echo "Task completed!"
```

### `continue` and `break`:

```bash
# Skip even numbers
for i in {1..10}; do
    if [ $((i % 2)) -eq 0 ]; then
        continue    # Skip this iteration
    fi
    echo "Odd: $i"
done

# Stop loop when limit hit
for i in {1..100}; do
    if [ $i -eq 10 ]; then
        break    # Exit loop entirely
    fi
    echo "$i"
done
```

---

## 6️⃣ How to read user input?

```bash
#!/bin/bash

# Basic read
read name
echo "Hello, $name"

# Read with prompt message
read -p "Enter your name: " name
echo "Hello, $name!"

# Read with timeout (5 seconds)
read -t 5 -p "Enter value (5s timeout): " value
if [ $? -ne 0 ]; then
    echo "Timeout! Using default value."
    value="default"
fi

# Read password (hidden input)
read -sp "Enter password: " password
echo ""    # New line after hidden input
echo "Password received (length: ${#password})"

# Read into array
read -a fruits -p "Enter fruits (space separated): "
echo "First fruit: ${fruits[0]}"
echo "All fruits: ${fruits[@]}"

# Read from file
while IFS= read -r line; do
    echo "→ $line"
done < config.txt

# Read with delimiter
IFS=',' read -ra items <<< "apple,banana,mango"
for item in "${items[@]}"; do
    echo "Item: $item"
done
```

---

## 7️⃣ What is `$?`?

`$?` is the **exit status** of the last executed command. It's crucial for error handling.

- `0` = success
- Any non-zero value (1–255) = failure

```bash
#!/bin/bash

# Check if previous command succeeded
ping -c 1 google.com > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Internet is reachable"
else
    echo "No internet connection!"
fi

# Common exit codes:
# 0   = Success
# 1   = General error
# 2   = Misuse of shell command
# 126 = Command found but not executable
# 127 = Command not found
# 130 = Script terminated with Ctrl+C

# Store exit status immediately (it changes after next command!)
ls /nonexistent/path 2>/dev/null
STATUS=$?
echo "Exit status was: $STATUS"

# Using || and && with exit status
mkdir /tmp/mydir && echo "Created successfully"
rm /nonexistent 2>/dev/null || echo "File not found, skipping"

# Return custom exit codes from functions/scripts
validate_input() {
    if [ -z "$1" ]; then
        echo "Error: Empty input"
        return 1     # Return non-zero = error
    fi
    return 0         # Success
}

validate_input ""
echo "Return value: $?"   # Prints: 1
```

---

## 8️⃣ What is the shebang (`#!`)?

The **shebang** (also called hashbang) is the first line of a script. It tells the OS **which interpreter** to use to run the script.

```bash
#!/bin/bash         # Use bash shell
#!/bin/sh           # Use POSIX sh (more portable)
#!/usr/bin/python3  # Run as Python 3 script
#!/usr/bin/env node # Run as Node.js script (portable path)
#!/usr/bin/perl     # Run as Perl script
```

### Why use `#!/usr/bin/env bash` vs `#!/bin/bash`?

```bash
#!/usr/bin/env bash    # More portable — finds bash in PATH
#!/bin/bash            # Hardcoded path — may fail if bash is elsewhere
```

> 💡 **Best practice**: Use `#!/usr/bin/env bash` for portability across systems.

```bash
# Without shebang: runs with current shell (may not be bash)
# With shebang: always runs with specified interpreter

# Check what shell is being used
echo $SHELL       # Your login shell
echo $0           # Current shell or script name
```

---

## 9️⃣ How to run a script?

```bash
# Step 1: Create the script
cat > myscript.sh << 'EOF'
#!/bin/bash
echo "Hello World"
EOF

# Step 2: Add execute permission
chmod +x myscript.sh

# Step 3: Run the script
./myscript.sh           # Run from current directory
bash myscript.sh        # Explicitly use bash
sh myscript.sh          # Use sh interpreter
/full/path/myscript.sh  # Use full path

# Run as root
sudo ./myscript.sh
sudo bash myscript.sh

# Run in background
./myscript.sh &
nohup ./myscript.sh &    # Keep running after logout

# Pass arguments
./myscript.sh arg1 arg2

# Source (run in current shell — variables persist)
source myscript.sh
. myscript.sh
```

---

## 🔟 How to debug a script?

Debugging helps find errors in shell scripts.

```bash
# Method 1: Run with -x flag (trace mode — prints each command before executing)
bash -x script.sh

# Method 2: Run with -v flag (verbose — prints script lines as they're read)
bash -v script.sh

# Method 3: Combine both
bash -xv script.sh

# Method 4: Add debug inside script
#!/bin/bash
set -x    # Turn on trace mode
# ... your code ...
set +x    # Turn off trace mode

# Method 5: set options for safer scripts
set -e    # Exit immediately if any command fails
set -u    # Treat unset variables as errors
set -o pipefail  # Catch errors in pipelines
set -x    # Trace mode

# Best practice - combine them:
set -euo pipefail

# Method 6: Debug specific section only
#!/bin/bash
echo "Before debug section"
set -x
# This section will be traced
result=$(ls /nonexistent 2>&1)
echo "Result: $result"
set +x
echo "After debug section"

# Method 7: echo statements for manual tracing
echo "[DEBUG] Variable value: $my_var"
echo "[DEBUG] About to run: $command"
```

---

# Part 4 — Advanced Shell Scripting

## 1️⃣ How do you handle functions in bash?

Functions allow you to organize code into reusable blocks.

```bash
#!/bin/bash

# Method 1: function keyword
function greet() {
    echo "Hello, $1!"
}

# Method 2: shorthand (more portable)
greet() {
    echo "Hello, $1!"
}

# Call function
greet "Hitesh"
greet "World"

# Function with return value
add_numbers() {
    local result=$(( $1 + $2 ))
    echo $result    # "Return" via echo/stdout
}

sum=$(add_numbers 10 20)
echo "Sum: $sum"

# Function with exit status
is_file_exists() {
    if [ -f "$1" ]; then
        return 0    # True/success
    else
        return 1    # False/failure
    fi
}

if is_file_exists "/etc/hosts"; then
    echo "File exists!"
fi

# Local variables (prevent polluting global scope)
my_function() {
    local local_var="I am local"
    global_var="I am global"
    echo "Inside function: $local_var"
}

my_function
echo "Global: $global_var"    # Works
echo "Local: $local_var"      # Empty — local variable not accessible outside

# Recursive function
factorial() {
    local n=$1
    if [ $n -le 1 ]; then
        echo 1
    else
        local prev=$(factorial $((n - 1)))
        echo $(( n * prev ))
    fi
}

echo "5! = $(factorial 5)"
```

---

## 2️⃣ What is the use of `case` statement?

`case` is a clean alternative to multiple `if-elif` conditions — especially useful for menus and option parsing.

```bash
#!/bin/bash

# Basic case statement
read -p "Enter your choice (1-3): " choice
case $choice in
    1)
        echo "You selected Option 1"
        ;;
    2)
        echo "You selected Option 2"
        ;;
    3)
        echo "You selected Option 3"
        ;;
    *)
        echo "Invalid choice!"
        ;;
esac

# Pattern matching
day=$(date +%A)
case $day in
    Monday|Tuesday|Wednesday|Thursday|Friday)
        echo "It's a weekday"
        ;;
    Saturday|Sunday)
        echo "It's the weekend!"
        ;;
esac

# Real-world: service manager script
SERVICE=$1
ACTION=$2

case $ACTION in
    start)
        systemctl start $SERVICE
        echo "$SERVICE started"
        ;;
    stop)
        systemctl stop $SERVICE
        echo "$SERVICE stopped"
        ;;
    restart)
        systemctl restart $SERVICE
        echo "$SERVICE restarted"
        ;;
    status)
        systemctl status $SERVICE
        ;;
    *)
        echo "Usage: $0 <service> {start|stop|restart|status}"
        exit 1
        ;;
esac
```

---

## 3️⃣ What are arrays in bash?

Arrays store multiple values in a single variable.

```bash
#!/bin/bash

# Declare and initialize array
fruits=("apple" "banana" "mango" "orange")

# Access elements (0-indexed)
echo "${fruits[0]}"     # apple
echo "${fruits[1]}"     # banana
echo "${fruits[-1]}"    # orange (last element)

# All elements
echo "${fruits[@]}"     # All elements
echo "${fruits[*]}"     # All elements as one string

# Number of elements
echo "${#fruits[@]}"    # 4

# Add element
fruits+=("grape")
fruits[5]="cherry"

# Loop over array
for fruit in "${fruits[@]}"; do
    echo "→ $fruit"
done

# Array with index
for i in "${!fruits[@]}"; do
    echo "[$i] = ${fruits[$i]}"
done

# Remove element
unset fruits[1]         # Remove "banana"

# Associative arrays (key-value pairs — like dictionaries)
declare -A person
person[name]="Hitesh"
person[age]=25
person[city]="Mumbai"

echo "Name: ${person[name]}"
echo "All keys: ${!person[@]}"
echo "All values: ${person[@]}"

# Practical: store server list
servers=("web1.example.com" "web2.example.com" "db1.example.com")
for server in "${servers[@]}"; do
    echo "Checking $server..."
    ping -c 1 $server > /dev/null && echo "✓ $server UP" || echo "✗ $server DOWN"
done
```

---

## 4️⃣ How to redirect output?

Linux has three standard streams: stdin (0), stdout (1), stderr (2).

| Symbol | Purpose |
|--------|---------|
| `>` | Redirect stdout to file (overwrite) |
| `>>` | Redirect stdout to file (append) |
| `2>` | Redirect stderr to file |
| `2>>` | Append stderr to file |
| `&>` | Redirect both stdout and stderr |
| `2>&1` | Merge stderr into stdout |
| `< file` | Use file as stdin |
| `/dev/null` | Discard output |

```bash
# Basic redirects
ls > filelist.txt           # Save output to file (overwrite)
ls >> filelist.txt          # Append output to file
ls /noexist 2> errors.txt   # Save errors to file
ls /noexist 2>> errors.txt  # Append errors

# Redirect both stdout and stderr
ls /valid /noexist &> all_output.txt
ls /valid /noexist > output.txt 2>&1   # Same effect

# Discard output (silence commands)
command > /dev/null 2>&1    # Completely silent
command 2>/dev/null         # Silence errors only

# Redirect to both screen and file (tee)
ls -l | tee output.txt          # Show AND save
ls -l | tee -a output.txt       # Show AND append

# Input redirect
mysql -u root -p database < dump.sql    # Feed SQL file
sort < unsorted.txt > sorted.txt        # Sort file

# Here-string
grep "pattern" <<< "This is the string to search"
```

---

## 5️⃣ What is a pipeline?

A pipeline (`|`) connects the **stdout of one command to the stdin of another**. This chains commands together to process data progressively.

```bash
# Basic pipeline
ls -l | grep ".sh"                    # Find .sh files
cat /etc/passwd | grep "hitesh"      # Find user
ps -ef | grep nginx                   # Find process

# Multiple pipes (pipeline chain)
cat /var/log/auth.log | grep "Failed" | awk '{print $11}' | sort | uniq -c | sort -rn | head -10
# ↑ Find top 10 IPs with failed SSH attempts

# Real-world pipeline examples
# Count lines in a file
cat file.txt | wc -l
wc -l < file.txt    # More efficient (no cat needed)

# Find and count processes
ps aux | grep nginx | grep -v grep | wc -l

# Monitor CPU-heavy processes
ps aux --sort=-%cpu | head -5

# Find unique IPs in web log
cat access.log | awk '{print $1}' | sort | uniq

# Pipeline with sed and awk
echo "Hello World 2024" | sed 's/World/Linux/' | awk '{print $1, $3}'

# Named pipe (FIFO)
mkfifo mypipe
command1 > mypipe &
command2 < mypipe
```

---

## 6️⃣ What is a here-document?

A here-document (heredoc) allows providing multi-line input to a command inline in the script.

```bash
#!/bin/bash

# Basic heredoc
cat << EOF
Hello World
This is a multi-line
text block
EOF

# Heredoc without variable expansion (use 'EOF' with quotes)
cat << 'EOF'
Variables like $HOME will NOT be expanded here
This is literal text
EOF

# Heredoc with variable expansion
NAME="Hitesh"
cat << EOF
Hello, $NAME!
Your home directory is: $HOME
Today is: $(date)
EOF

# Write file using heredoc
cat > /etc/myapp/config.conf << EOF
APP_NAME=MyApp
PORT=8080
DEBUG=false
LOG_LEVEL=info
EOF

# Send email with heredoc
mail -s "Alert" admin@example.com << EOF
Dear Admin,

Disk usage on $(hostname) has exceeded 80%.
Current usage: $(df -h / | tail -1 | awk '{print $5}')

Please take action.

Regards,
Monitoring System
EOF

# Pass SQL via heredoc
mysql -u root -p << SQL
USE mydb;
SELECT * FROM users WHERE active=1;
QUIT
SQL
```

---

## 7️⃣ What is the `trap` command?

`trap` catches **signals** (interrupts) and executes a function/command when they occur.

```bash
#!/bin/bash

# Catch Ctrl+C (SIGINT)
trap "echo 'Ctrl+C pressed! Exiting...'; exit 1" SIGINT

# Cleanup on exit
cleanup() {
    echo "Cleaning up temporary files..."
    rm -f /tmp/script_temp_*
    echo "Cleanup done."
}
trap cleanup EXIT    # Always run cleanup when script exits

# Common signals
# SIGINT  (2)  = Ctrl+C
# SIGTERM (15) = kill command (graceful termination)
# SIGKILL (9)  = kill -9 (cannot be caught!)
# SIGHUP  (1)  = Terminal closed / reload config
# EXIT         = Script exits (any reason)
# ERR          = Any command fails

# Real-world example: database backup with cleanup
BACKUP_FILE="/tmp/backup_$(date +%F).sql"

trap "rm -f $BACKUP_FILE; echo 'Backup interrupted and temp file removed'; exit 1" SIGINT SIGTERM

echo "Starting backup..."
mysqldump -u root mydb > $BACKUP_FILE
echo "Backup complete: $BACKUP_FILE"

# Temporarily ignore a signal
trap "" SIGINT    # Ignore Ctrl+C
echo "Critical section - cannot be interrupted"
sleep 5
trap SIGINT       # Restore default behavior
```

---

## 8️⃣ What is the difference between `==` and `-eq`?

| Operator | Type | Used For |
|----------|------|---------|
| `==` or `=` | String operator | Comparing text/strings |
| `-eq` | Arithmetic operator | Comparing integers |

```bash
#!/bin/bash

# String comparison with ==
name1="hitesh"
name2="hitesh"
if [ "$name1" == "$name2" ]; then
    echo "Names are equal"
fi

# WRONG: Using == for numbers (compares as strings, not values!)
if [ "10" == "9" ]; then
    echo "This is string comparison — '10' is not '9' as strings"
fi

# Correct: Using -eq for numbers
num1=10
num2=10
if [ $num1 -eq $num2 ]; then
    echo "Numbers are equal"
fi

# The difference matters:
# String "10" > "9" is FALSE (because "1" < "9" alphabetically)
# Integer 10 > 9 is TRUE
if [ "10" \> "9" ]; then
    echo "Wrong! String comparison: '10' is NOT > '9'"
fi
if [ 10 -gt 9 ]; then
    echo "Correct! Integer comparison: 10 > 9"
fi

# Summary of comparison operators:
# Strings: == != < > -z (empty) -n (not empty)
# Integers: -eq -ne -gt -lt -ge -le
```

---

## 9️⃣ How to check if a file or directory exists?

```bash
#!/bin/bash

# File checks
if [ -f "/etc/hosts" ]; then
    echo "File exists"
fi

if [ ! -f "/tmp/missing.txt" ]; then
    echo "File does NOT exist"
fi

# Directory checks
if [ -d "/var/log" ]; then
    echo "Directory exists"
fi

# Readable, writable, executable
if [ -r "/etc/hosts" ]; then echo "File is readable"; fi
if [ -w "/tmp/test.txt" ]; then echo "File is writable"; fi
if [ -x "/usr/bin/bash" ]; then echo "File is executable"; fi

# File not empty
if [ -s "/var/log/syslog" ]; then
    echo "Log file is not empty"
fi

# Comprehensive example
check_file() {
    local file="$1"
    
    if [ ! -e "$file" ]; then
        echo "Error: $file does not exist"
        return 1
    fi
    
    [ -f "$file" ] && echo "Type: Regular file"
    [ -d "$file" ] && echo "Type: Directory"
    [ -L "$file" ] && echo "Type: Symbolic link"
    [ -r "$file" ] && echo "Readable: Yes" || echo "Readable: No"
    [ -w "$file" ] && echo "Writable: Yes" || echo "Writable: No"
    [ -x "$file" ] && echo "Executable: Yes" || echo "Executable: No"
}

check_file "/etc/hosts"
```

---

## 🔟 What is `set -e` in bash?

`set -e` makes the script **exit immediately** when any command returns a non-zero exit status (i.e., fails).

```bash
#!/bin/bash
set -e    # Exit on error

echo "Step 1: Starting"
cp /etc/hosts /tmp/hosts_backup    # If this fails, script stops
echo "Step 2: File copied"
ls /nonexistent/dir                # This fails — script exits here
echo "Step 3: Never reached"      # This will NOT execute
```

### Recommended Script Safety Settings:

```bash
#!/bin/bash
set -euo pipefail

# -e  = Exit on error
# -u  = Treat unset variables as errors
# -o pipefail = Exit if any part of a pipe fails
```

### Bypassing `set -e` when needed:

```bash
set -e

# Use || true to allow a command to fail without exiting
rm /tmp/file.txt || true         # Won't stop script if file missing

# Use if-statement (doesn't trigger set -e)
if ! some_command; then
    echo "Command failed, handling it..."
fi

# Temporarily disable
set +e    # Turn off exit-on-error
risky_command
set -e    # Turn it back on
```

---

# Part 5 — Linux Directory Structure

The Linux filesystem follows the **Filesystem Hierarchy Standard (FHS)** which standardizes directory structure across all distributions.

```
/
├── bin      → Essential user commands
├── boot     → Bootloader and kernel files
├── dev      → Device files
├── etc      → Configuration files
├── home     → User home directories
├── lib      → Shared system libraries
├── media    → Auto-mounted removable media
├── mnt      → Temporary mount points
├── opt      → Optional/third-party software
├── proc     → Virtual filesystem (process/kernel info)
├── root     → Root user's home directory
├── run      → Runtime data (cleared on reboot)
├── sbin     → System administration commands
├── srv      → Service data
├── sys      → Kernel/hardware interface
├── tmp      → Temporary files
├── usr      → User programs and utilities
└── var      → Variable data (logs, cache, mail)
```

### Quick Reference Table:

| Directory | Purpose | Examples |
|-----------|---------|---------|
| `/bin` | Basic commands (all users) | `ls`, `cp`, `mv`, `cat`, `echo` |
| `/sbin` | Admin commands (root) | `fsck`, `mount`, `shutdown`, `iptables` |
| `/etc` | System configuration | `/etc/passwd`, `/etc/fstab`, `/etc/ssh/` |
| `/home` | User data | `/home/hitesh`, `/home/user1` |
| `/root` | Root user home | `/root/.bashrc` |
| `/boot` | Startup files | `vmlinuz`, `grub/`, `initrd.img` |
| `/dev` | Device files | `/dev/sda`, `/dev/null`, `/dev/tty` |
| `/lib` | Shared libraries | `libc.so`, `libm.so` |
| `/tmp` | Temporary files | Session data, temp downloads |
| `/usr` | Installed apps | `/usr/bin/python3`, `/usr/lib/` |
| `/var` | Changing data | `/var/log/`, `/var/cache/`, `/var/mail/` |
| `/proc` | Process/kernel info | `/proc/cpuinfo`, `/proc/meminfo` |
| `/opt` | Optional software | `/opt/google/chrome`, `/opt/docker/` |
| `/mnt` | Manual mounts | `mount /dev/sdb1 /mnt` |
| `/media` | Auto-mounted media | `/media/usb`, `/media/cdrom` |

---

# Part 6 — Linux Boot Process

## Complete Boot Flow:

```
Power ON
    ↓
BIOS / UEFI → POST (Power-On Self Test) → Detects hardware
    ↓
Bootloader (GRUB) → Loads kernel + initramfs into memory
    ↓
Linux Kernel → Initializes drivers, mounts root filesystem
    ↓
systemd (PID 1) → Starts services and targets
    ↓
Login Prompt (CLI or GUI)
```

## Stage 1 — BIOS / UEFI

- Performs **POST** (Power-On Self Test)
- Detects and initializes hardware (CPU, RAM, disk, keyboard)
- Finds bootable device from configured boot order
- Loads bootloader from **MBR** (legacy) or **EFI partition** (modern UEFI)

| BIOS | UEFI |
|------|------|
| Legacy standard | Modern replacement |
| Uses MBR (512 bytes) | Uses GPT partition table |
| Limited to 2TB drives | Supports drives >2TB |
| Slower boot | Faster boot |
| Basic text interface | Graphical interface possible |

## Stage 2 — GRUB Bootloader

- Located at `/boot/grub/`
- Presents boot menu (OS selection, kernel version selection)
- Loads the kernel (`/boot/vmlinuz-*`) and initramfs (`/boot/initrd.img-*`) into memory
- Passes kernel parameters (e.g., `quiet splash`)

```bash
# View/edit GRUB config
cat /etc/default/grub
sudo update-grub

# GRUB command line (if GRUB fails to boot, press 'e' to edit)
# grub rescue> — appears when GRUB is broken

# Fix broken GRUB:
grub-install /dev/sda
update-grub
```

## Stage 3 — Linux Kernel

- Decompresses itself into memory
- Initializes CPU, memory management, device drivers
- Mounts temporary root filesystem from **initramfs**
- Detects and loads hardware modules
- Mounts actual root filesystem (`/`)
- Starts the first user-space process: **systemd** (PID 1)

```bash
uname -r             # Show kernel version
dmesg                # View kernel boot messages
dmesg | grep -i error  # Check for hardware errors during boot
ls /boot/            # View available kernels
```

## Stage 4 — systemd

- First userspace process (**PID = 1**)
- Manages all services, mounts, and targets
- Parallel service startup (faster than old `init`)

```bash
ps -p 1             # Verify PID 1 is systemd
systemd-analyze     # Show total boot time
systemd-analyze blame   # Time taken by each service
systemd-analyze critical-chain  # Critical path in boot

systemctl list-units --type=service    # All services
systemctl get-default                  # Current boot target
```

## Stage 5 — Targets (Replaced Runlevels)

| Old Runlevel | systemd Target | Purpose |
|-------------|----------------|---------|
| 0 | `poweroff.target` | Shutdown |
| 1 | `rescue.target` | Single-user mode |
| 3 | `multi-user.target` | CLI only |
| 5 | `graphical.target` | GUI desktop |
| 6 | `reboot.target` | Reboot |

```bash
systemctl get-default                         # Current target
systemctl set-default multi-user.target       # Set CLI mode
systemctl set-default graphical.target        # Set GUI mode
systemctl isolate rescue.target               # Switch to rescue mode now
```

---

# Part 7 — System Administration

## User Management:

```bash
# Add user
useradd hitesh                         # Create user
useradd -m -s /bin/bash hitesh         # With home dir and bash shell
passwd hitesh                          # Set password

# Modify user
usermod -aG sudo hitesh                # Add to sudo group
usermod -s /bin/zsh hitesh             # Change shell
usermod -d /new/home hitesh            # Change home directory
usermod -l newhitesh hitesh            # Rename user

# Delete user
userdel hitesh                         # Delete user (keep home)
userdel -r hitesh                      # Delete user + home directory

# View user info
id hitesh                              # UID, GID, groups
cat /etc/passwd | grep hitesh          # User entry
groups hitesh                          # Group memberships
```

## Service Management with systemctl:

```bash
systemctl status nginx          # Check service status
systemctl start nginx           # Start service
systemctl stop nginx            # Stop service
systemctl restart nginx         # Restart service
systemctl reload nginx          # Reload config (no downtime)
systemctl enable nginx          # Auto-start on boot
systemctl disable nginx         # Remove from boot startup
systemctl is-active nginx       # Check if running (returns 0 or non-zero)
systemctl list-units --failed   # List failed services
```

---

# Part 8 — DevOps-Focused Linux

## Process Management:

```bash
# List processes
ps -ef | grep nginx            # Find process
ps aux --sort=-%cpu | head     # Top CPU consumers

# Kill processes
kill PID                       # Send SIGTERM (graceful)
kill -9 PID                    # Send SIGKILL (force)
kill -15 PID                   # Send SIGTERM explicitly
killall nginx                  # Kill all processes named nginx
pkill -u hitesh                # Kill all processes by user

# Background/foreground
command &                      # Run in background
jobs                           # List background jobs
fg %1                          # Bring job 1 to foreground
bg %1                          # Send to background
nohup command &                # Persist after logout
```

## Network Commands:

```bash
ss -tulnp                      # Show all listening ports
ss -tp                         # TCP connections
curl -I https://example.com    # Get HTTP headers
curl -o file.txt https://url   # Download file
wget https://url/file.zip      # Download file
scp file.txt user@server:/path # Copy file over SSH
rsync -avz /src user@host:/dst # Sync files over SSH
```

## Firewall (ufw / iptables):

```bash
# UFW (Ubuntu)
ufw status
ufw allow 80/tcp
ufw allow ssh
ufw deny 3306
ufw enable

# iptables
iptables -L -n                 # List rules
iptables -A INPUT -p tcp --dport 80 -j ACCEPT   # Allow port 80
iptables -A INPUT -j DROP      # Drop all other input
```

---

# Part 9 — Practical Shell Script Examples

## 1. Directory Backup Script:

```bash
#!/bin/bash
set -euo pipefail

SRC="/home/user/data"
DEST="/backup"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$DEST/backup_$DATE.tar.gz"

mkdir -p "$DEST"

echo "[$(date)] Starting backup of $SRC..."
tar -czf "$BACKUP_FILE" "$SRC"
echo "[$(date)] Backup saved: $BACKUP_FILE"
echo "[$(date)] Size: $(du -sh $BACKUP_FILE | cut -f1)"
```

## 2. Disk Usage Alert Script:

```bash
#!/bin/bash
THRESHOLD=80
FILESYSTEM="/"

USAGE=$(df "$FILESYSTEM" | tail -1 | awk '{print $5}' | cut -d'%' -f1)

if [ "$USAGE" -gt "$THRESHOLD" ]; then
    echo "ALERT: Disk usage on $FILESYSTEM is ${USAGE}% (threshold: ${THRESHOLD}%)"
    df -h "$FILESYSTEM"
    # Send email
    # mail -s "Disk Alert on $(hostname)" admin@example.com <<< "Disk is $USAGE% full"
else
    echo "OK: Disk usage is ${USAGE}%"
fi
```

## 3. Service Health Check:

```bash
#!/bin/bash
SERVICES=("nginx" "mysql" "redis")

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✓ $service is running"
    else
        echo "✗ $service is DOWN — attempting restart..."
        systemctl restart "$service" && echo "  → Restarted successfully" || echo "  → Restart FAILED!"
    fi
done
```

## 4. Bulk User Creation from File:

```bash
#!/bin/bash
USER_FILE="users.txt"

if [ ! -f "$USER_FILE" ]; then
    echo "Error: $USER_FILE not found"
    exit 1
fi

while IFS=',' read -r username password group; do
    if id "$username" &>/dev/null; then
        echo "User $username already exists, skipping..."
        continue
    fi
    
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    usermod -aG "$group" "$username"
    echo "Created user: $username (group: $group)"
done < "$USER_FILE"
```

## 5. Even or Odd Number Check:

```bash
#!/bin/bash
read -p "Enter a number: " num

if ! [[ "$num" =~ ^-?[0-9]+$ ]]; then
    echo "Error: '$num' is not a valid integer"
    exit 1
fi

if [ $(( num % 2 )) -eq 0 ]; then
    echo "$num is EVEN"
else
    echo "$num is ODD"
fi
```

---

# Quick Reference Cheatsheet

## File Operations:

```bash
ls -lah            # List all files with details
cp -r src/ dest/   # Copy directory recursively
mv file.txt /tmp/  # Move file
rm -rf directory/  # Remove directory forcefully
mkdir -p a/b/c     # Create nested directories
touch file.txt     # Create empty file or update timestamp
cat file.txt       # Print file contents
less file.txt      # Paginated file view
wc -l file.txt     # Count lines
sort file.txt      # Sort lines
uniq file.txt      # Remove duplicate lines
cut -d: -f1 /etc/passwd  # Extract first field
awk '{print $1}' file    # Print first column
sed 's/old/new/g' file   # Replace text
```

## Process Management:

```bash
ps aux             # All processes
top / htop         # Real-time monitor
kill -9 PID        # Force kill
jobs               # Background jobs
nohup cmd &        # Run persistently
```

## Permissions:

```bash
chmod 755 file     # rwxr-xr-x
chmod +x file      # Add execute
chown user:group file  # Change owner
```

## Networking:

```bash
ip addr show       # Show IPs
ss -tulnp          # Open ports
ping host          # Test connectivity
curl -I url        # HTTP headers
wget url           # Download
```

## Shell Scripting:

```bash
#!/bin/bash
set -euo pipefail          # Safe script settings
VAR=$(command)             # Command substitution
[ -f file ]                # File test
$1, $2, $#, $@, $?         # Special variables
if/elif/else/fi            # Conditionals
for x in list; do; done    # For loop
while [ cond ]; do; done   # While loop
function_name() { }        # Define function
trap cleanup EXIT          # Signal handling
```

---

*This document covers Linux Commands and Shell Scripting from beginner to DevOps-level. Practice these concepts hands-on for best results.*