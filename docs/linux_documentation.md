# Linux Commands & Shell Scripting — Complete Reference

A comprehensive guide to Linux commands and shell scripting: concepts, commands, and real-world examples.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Shell & Terminal Basics](#shell--terminal-basics)
3. [File & Directory Commands](#file--directory-commands)
4. [Permissions & Ownership](#permissions--ownership)
5. [Users, Groups & Access](#users-groups--access)
6. [Searching & Text Processing](#searching--text-processing)
7. [Networking](#networking)
8. [Archives & Compression](#archives--compression)
9. [Package Management](#package-management)
10. [System Monitoring & Resources](#system-monitoring--resources)
11. [Process Management](#process-management)
12. [Scheduling (cron & at)](#scheduling-cron--at)
13. [Logs](#logs)
14. [Links (Soft vs Hard)](#links-soft-vs-hard)
15. [SELinux](#selinux)
16. [Encoding & Misc Utilities](#encoding--misc-utilities)
17. [Shell Scripting Basics](#shell-scripting-basics)
18. [Advanced Shell Scripting](#advanced-shell-scripting)
19. [I/O Redirection & Pipelines](#io-redirection--pipelines)
20. [Linux Directory Structure](#linux-directory-structure)
21. [Linux Boot Process](#linux-boot-process)
22. [Practical Shell Script Examples](#practical-shell-script-examples)
23. [Quick Reference Cheatsheet](#quick-reference-cheatsheet)

---

## Core Concepts

### What Is a Terminal?
- Terminal (terminal emulator): the window you type into (e.g. GNOME Terminal, iTerm, Windows Terminal)
- Shell: the program that reads and runs your commands (bash, zsh, etc.)
- CLI (Command Line Interface): interacting with the OS via typed text instead of clicking (GUI)
- The terminal displays it, the shell interprets and executes it

### Linux = Kernel vs. OS vs. Distro
- **Linux** = just the kernel (created by Linus Torvalds in 1991)
- A **distribution (distro)** = kernel + GNU tools + package manager + desktop, e.g., Ubuntu, Fedora, Debian
- "Linux OS" is really **GNU/Linux** — the GNU userland tools (bash, coreutils, etc.) run on top of the Linux kernel

### Open Source & Licensing
- Linux is released under the **GPL** (GNU General Public License)
- Source code is free to view, modify, and redistribute
- This is why so many distros exist — anyone can fork and customize it

### Monolithic Kernel vs. Microkernel
- Linux uses a **monolithic kernel** (all core services run in kernel space for performance)
- **Kernel space**: where the kernel runs, has direct hardware access
- **User space**: where normal applications/programs run, isolated for stability/security
- **System calls** are the bridge between the two

### Everything Is a File
One of Linux's core design philosophies: as much as possible is represented and accessed as a file, not just documents and folders.
- Hardware devices → `/dev/sda`, `/dev/null`, `/dev/tty`
- Running process info → `/proc/1234/`
- Kernel/hardware settings → `/sys/`
- Even network sockets and pipes behave like files (can be read/written)

This is why permissions (`chmod`, `chown`) apply almost everywhere, and why redirecting into `/dev/null` "just works" — it's a file like any other, it just happens to discard whatever is written to it.

### File extensions don't matter in Linux
Unlike Windows, Linux doesn't rely on file extensions to determine file type or how to open a file — .txt, .sh, or no extension at all makes no functional difference to the OS. What makes a file "executable" is its permission bits (x), not its name. file filename tells you the actual type by inspecting its content, not its name.

### Multi-user, Multitasking Nature
- Linux was designed from the ground up to let multiple users run multiple processes simultaneously
- This is why permissions (owner/group/others) exist at all — a direct consequence of being multi-user

### Case Sensitivity
Unlike Windows, Linux treats uppercase and lowercase as completely different characters everywhere — filenames, commands, and variables.
```bash
touch File.txt file.txt    # creates TWO separate files
cd Documents               # fails if the real folder is "documents"
NAME="Hi"; name="Bye"      # two different variables
```

### Processes, Threads & Process States

- **Process vs thread**: a thread is a lightweight unit within a process, sharing memory.
- **fork()**: creates a new process by duplicating the calling process.
- **exec()**: replaces the current process with another program.
- **Process states**: Running, Sleeping, Zombie (finished but not reaped by parent), Orphan (parent died first).

### What Is a Daemon?
A **daemon** is a background process with no controlling terminal, usually started at boot and running for the system's lifetime (e.g. `sshd`, `crond`, `systemd`). By convention many daemon names end in `d`. You interact with most daemons via `systemctl` rather than by talking to them directly.

#### `exec` Command

The shell builtin `exec` replaces the current shell process with the specified program.

```bash
exec /bin/bash
```

### Swap Space & Virtual Memory
When physical RAM fills up, the kernel moves inactive memory pages to disk (swap) to free RAM — a core OS memory-management concept.

### Mounting, /etc/fstab & Partitions
- A **partition** is a physical/logical division of a disk
- **Mounting** attaches a filesystem (partition, USB drive, network share) to a directory in the tree so it becomes accessible
- `/etc/fstab` defines what gets mounted automatically at boot
- This ties into why `/mnt` and `/media` exist in the directory structure

### Shells Are Interchangeable
- `bash` (most common default), `sh`/`dash` (POSIX, lighter, faster), `zsh`, `fish`, `ksh`
- Your default shell is set in `/etc/passwd` and can be changed with `chsh`

### Init Systems Beyond systemd
- **SysVinit** (older, sequential scripts in `/etc/init.d`)
- **Upstart** (used briefly by older Ubuntu)
- **systemd** is now the modern standard on most distros, but not universal (some minimal distros still avoid it)

### Display Server / Desktop Environment (GUI)
- **X11 vs Wayland** — the underlying display server protocols
- **Desktop environment** (GNOME, KDE, XFCE) vs **window manager** — different layers of the GUI stack

### Containers vs. Virtual Machines
- A **VM** virtualizes entire hardware + OS via a hypervisor
- A **container** (Docker, etc.) shares the host kernel but isolates processes using namespaces and cgroups

### POSIX Compliance
POSIX (Portable Operating System Interface) is a set of IEEE standards specifying how Unix-like operating systems should behave (commands, APIs, shell behavior, utilities). The goal is portability — a script written for one POSIX-compliant system should run on another with little or no modification.

---

## Shell & Terminal Basics

### Arguments vs Options/Flags
```text
command [options] [arguments]

cp -r myfolder backup/
     |  |         |
     |  |         +-- arguments: what the command acts on (source, destination)
     |  +------------ argument
     +--------------- option/flag: modifies HOW the command behaves
# single-dash flags can be combined like ls -la = ls -l -a
# Double-dash flags are always spelled out (--help, --verbose) and can't be combined
```

### Reading the Prompt

The shell prompt itself tells you who you are:
```text
hitesh@server:~$    # ends in $ -> normal user
root@server:~#      # ends in # -> root (superuser)
```
Always double-check for that `#` before running anything destructive — it means every command runs with full system privileges.

### Navigating the Filesystem

```bash
pwd              # print current directory
cd               # no argument -> takes you straight to home directory (same as cd ~)
cd /path/to/dir  # absolute path
cd ~             # go to home directory
cd -             # go to previous directory
cd ./-           # View dashed filename "-"
cd .             # Current Directory
cd ..            # Parent Directory or the directory immediately above the current one
whoami           # print current logged-in username
clear            # clear the terminal screen
exit             # close the current shell session
```

### Chaining Commands
```bash
cmd1 ; cmd2         # Run cmd1, then cmd2 regardless of whether cmd1 succeeded
cmd1 && cmd2        # Run cmd2 ONLY IF cmd1 succeeded (exit status 0)
cmd1 || cmd2        # Run cmd2 ONLY IF cmd1 failed (non-zero exit status)

mkdir backup && cd backup          # cd only runs if mkdir succeeded
ping -c 1 google.com || echo "No internet"
apt update && apt upgrade && apt autoremove   # chain multiple steps, stop if any fails
```

**Why this works — conceptually:** every command returns an exit status (`$?`) of `0` (success) or non-zero (failure). `&&` and `||` are short-circuit operators that check that status:

| Left command | Operator | Right command runs? |
|---|---|---|
| Succeeds (0) | `&&` | Yes |
| Fails (non-zero) | `&&` | No |
| Succeeds (0) | `\|\|` | No |
| Fails (non-zero) | `\|\|` | Yes |

### echo — Print Text to the Terminal

```bash
echo Hello                  # Hello
echo "Hello World"          # Hello World
echo 'Hello World'          # Hello World (same, no expansion happening here anyway)
echo $USER                  # prints current username
echo "User: $USER"          # User: hitesh

echo -n "No newline"        # suppresses trailing newline
echo -e "Line1\nLine2\tTabbed"   # -e enables \n, \t escape sequences
echo "Line1\nLine2"          # without -e, \n prints literally
```
> `echo` is the most-used command in shell scripts — for printing messages, debugging variable values, and building strings. See [printf vs echo](#printf-vs-echo) later for formatted output.

### Absolute vs Relative Paths

```bash
cd /home/hitesh/projects   # absolute - works from anywhere
cd projects                # relative - only works if you're already in /home/hitesh
```
- **Absolute path**: starts from root (`/`), always points to the same location, e.g. `/home/hitesh/projects/app.sh`
- **Relative path**: starts from your current directory (`pwd`), e.g. `./app.sh` or `../projects/app.sh`

### Quoting Rules
- `'single quotes'` → literal, no variable expansion
- `"double quotes"` → allows `$variable` expansion
- `` `backticks` `` / `$(command)` → command substitution
- `echo $var` can break with spaces/globbing but `echo "$var"` doesn't

```bash
name=`whoami`     # Old style — harder to nest, avoid in new scripts
name=$(whoami)    # Preferred — nests cleanly, more readable
```

### Wildcards / Globbing

Globbing lets the shell (not the command) expand patterns into matching filenames before the command runs. `ls *.txt` doesn't ask `ls` to interpret `*` — bash expands `*.txt` into actual filenames first, and `ls` just receives a plain list.

| Pattern | Meaning | Example match |
|---|---|---|
| `*` | Zero or more of any character | `*.log` → `app.log`, `error.log` |
| `?` | Exactly one character | `file?.txt` → `file1.txt`, not `file10.txt` |
| `[abc]` | One character from the set | `file[123].txt` → `file1.txt`, `file2.txt`, `file3.txt` |
| `[a-z]` | One character in a range | `[A-Z]*` → files starting with uppercase |
| `[!abc]` / `[^abc]` | One character NOT in the set | `file[!1].txt` → anything except `file1.txt` |
| `{a,b,c}` | Brace expansion (bash-specific) | `file.{txt,log}` → `file.txt file.log` |

```bash
ls *.sh                  # all shell scripts
rm backup_*.tar.gz       # delete all matching backups
cp report{,.bak}         # expands to: cp report report.bak
mv file?.txt archive/    # only single-char-suffix files
```
What does nullglob do?
If a wildcard (*, *.txt, etc.) doesn't match any file, Bash normally keeps the wildcard as it is.
```bash
echo *.txt               # Without nullglob output: *.txt
shopt -s nullglob
echo *.txt               # output:
```

> **Gotcha:** if no file matches the pattern, bash (by default) passes the literal pattern string to the command instead of an empty list — e.g. `ls *.xyz` with no `.xyz` files prints `ls: cannot access '*.xyz'`.
> **Globbing is not regex.** `*` in globbing means "anything," but in regex `*` means "zero or more of the previous character." `grep` uses regex; `ls`/`rm`/`cp` use globbing.

### Getting Help

```bash
man ls              # full manual page: description, all options, examples
man -k copy         # search man page descriptions for "copy" (like apropos)
apropos copy        # same as `man -k copy` — search man page descriptions by keyword
ls --help           # short built-in usage summary (most GNU commands support this)
whatis ls           # one-line description only
bash --version       # Check installed version of a program (works for most: git --version, python3 --version, curl --version)
info ls             # some tools have more detailed "info" documentation (GNU-specific)
```

Navigating man pages: `Space`/`f` page down · `b` page up · `/searchterm` search inside the page, `n` next match · `q` quit

> Rule of thumb: `--help` for a quick reminder of flags you half-remember; `man` when you need real depth (exit codes, edge cases, "SEE ALSO" section).

### which / whereis / type

These all answer "where does this command actually come from?" — but answer slightly different questions.

```bash
which python3
# /usr/bin/python3
# -> Searches your $PATH and shows the exact executable that would run

whereis python3
# python3: /usr/bin/python3 /usr/lib/python3.10 /usr/share/man/man1/python3.1.gz
# -> Shows binary + source + man page locations (broader search, not just $PATH)

type cd
# cd is a shell builtin
# -> Tells you HOW the command resolves: builtin, alias, function, or file

type -a python    # shows ALL matches (alias, function, AND binary) if there are multiple

command -v python3    # POSIX-portable way to check if a command exists (scriptable, unlike `which`)
```

Why this matters:
- If you have two versions of a command installed, `which` tells you which one will actually execute
- `type` catches things `which` misses — e.g. if `ll` is an alias, `which ll` might say "not found" while `type ll` shows the alias definition
- Useful for debugging "command not found" or "wrong version is running" issues, especially with `$PATH` problems

### date — Show or Format the Current Date/Time

```bash
date                          # Sat Aug 15 10:30:00 IST 2026
date +%Y-%m-%d                # 2026-08-15
date +%H:%M:%S                # 10:30:00
date +"%A, %d %B %Y"          # Saturday, 15 August 2026
date -d "3 days ago"          # date 3 days in the past (GNU date)
date -d "next monday"         # upcoming Monday's date
```
| Format | Meaning |
|---|---|
| `%Y` | 4-digit year | 
| `%m` | Month (01-12) |
| `%d` | Day (01-31) |
| `%H:%M:%S` | Hour:Minute:Second (24h) |
| `%A` | Full weekday name |

### cal — Calendar

```bash
cal                # current month
cal 2026            # whole year
cal 8 2026          # August 2026
```

### alias — Shortcuts for Frequently Used Commands

An alias maps a short word to a longer command string, expanded by the shell before execution.

```bash
alias ll='ls -la'
alias gs='git status'
alias ..='cd ..'
alias ...='cd ../..'
alias rm='rm -i'          # safer rm - always confirms before deleting
```

Checking and removing aliases:
```bash
alias             # list all currently defined aliases
alias ll          # show what "ll" expands to
unalias ll        # remove it for this session
```

> Aliases defined on the command line only last for the current terminal session. To make them permanent, add them to `~/.bashrc` and reload with `source ~/.bashrc`.

> **Limitation:** aliases are simple text substitution — no positional logic or conditionals. For that, write a function instead:
```bash
mkcd() { mkdir -p "$1" && cd "$1"; }   # a function, not an alias
```

### Command History Shortcuts

Bash keeps a record of commands you've run, stored in `~/.bash_history` (written when the shell exits).

```bash
history              # list all commands with numbers
history 20           # last 20 commands only
history -c           # clear history for this session
```

### Bash History Configuration

Bash provides environment variables that control how command history is stored and handled.

```bash
HISTCONTROL=ignoredups:ignorespace
HISTFILE=/root/.bash_history
HISTFILESIZE=2000
HISTSIZE=1000
```

#### `HISTCONTROL`

Controls how Bash handles commands before adding them to history.

```bash
HISTCONTROL=ignoredups
```

`ignoredups` prevents consecutive duplicate commands from being stored.

```bash
HISTCONTROL=ignorespace
```

`ignorespace` prevents commands that begin with a space from being saved to history.

Both can be enabled together:

```bash
HISTCONTROL=ignoredups:ignorespace
```

Example:

```bash
echo hello
 echo secret-command
```

The second command begins with a space, so with `ignorespace` enabled, it is not saved to history.

> `ignorespace` is not a security mechanism. A command typed with a leading space may still appear through other logging or auditing mechanisms.

#### `HISTFILE`

Specifies the file used to save Bash command history.

```bash
echo "$HISTFILE"
```

For the root account, a typical value is:

```bash
HISTFILE=/root/.bash_history
```

For a normal user, it is commonly:

```bash
HISTFILE=~/.bash_history
```

#### `HISTSIZE`

Controls how many commands Bash keeps in the current shell's in-memory history list.

```bash
HISTSIZE=1000
```

This means the shell keeps up to 1000 history entries in memory.

Check the current value:

```bash
echo "$HISTSIZE"
```

#### `HISTFILESIZE`

Controls how many history lines are retained in the history file when Bash writes history to disk.

```bash
HISTFILESIZE=2000
```

This can be different from `HISTSIZE`.

```text
HISTSIZE      → commands remembered by the current shell
HISTFILESIZE  → lines retained in the history file
```

#### Search Command History

```bash
history | grep cat
```

This displays history entries containing `cat`.

For a case-insensitive search:

```bash
history | grep -i "cat"
```

You can also search the Bash configuration file for history-related settings:

```bash
grep -i "hist" ~/.bashrc
```

> Use `~/.bashrc` rather than `.bashrc` when you want to explicitly refer to the Bash configuration file in your home directory.

#### Check Your Current History Settings

```bash
echo "$HISTCONTROL"
echo "$HISTFILE"
echo "$HISTSIZE"
echo "$HISTFILESIZE"
```

> These variables can be set for the current shell by assigning them directly. To make them persistent for future interactive Bash sessions, place the desired settings in the appropriate Bash startup configuration, commonly `~/.bashrc`.

| Shortcut | Effect |
|---|---|
| `!!` | Repeat the last command |
| `!n` | Repeat command number `n` from `history` |
| `!string` | Repeat the last command starting with `string` |
| `!string:p` | Print the command without running it (preview) |
| `Ctrl+R` | Reverse search — type part of a past command, fuzzy-matches as you type |
| `↑` / `↓` | Step backward/forward through history one at a time |
| `!$` | Last argument of the previous command |
| `!*` | All arguments of the previous command |

Terminal control shortcuts:
```text
Ctrl+C  -> interrupt/kill current running command
Ctrl+D  -> send EOF, exits shell or logs out if line is empty
Ctrl+L  -> clear the terminal screen (same as `clear`)
Ctrl+A  -> jump cursor to start of line
Ctrl+E  -> jump cursor to end of line
Ctrl+Shift+C  -> copy (in most Linux terminals)
Ctrl+Shift+V  -> paste
(Ctrl+C / Ctrl+V are NOT copy-paste in the terminal — Ctrl+C interrupts a running command)

cd Doc<Tab>          # completes to "cd Documents/" if it's the only match
cat my_lo<Tab>       # completes filenames as you type
ls -<Tab><Tab>       # press Tab twice to see ALL available options for a command
```
Practical examples:
```bash
sudo !!                       # re-run last command, but with sudo (classic fix for "permission denied")
mkdir new_project && cd !$    # cd into "new_project" using !$ instead of retyping it
```

Ctrl+R workflow: press `Ctrl+R` → type a fragment (e.g. `docker`) → bash shows the most recent match → press `Ctrl+R` again to cycle older matches, `Enter` to run, or `→`/`Esc` to edit before running.

### xargs

Many commands (`rm`, `chmod`, `mkdir`) don't read from stdin — they only accept arguments directly on the command line. `xargs` bridges that gap: it takes lines from stdin and converts them into arguments for another command.

```bash
find . -name "*.tmp" | xargs rm              # delete every .tmp file found
echo "file1.txt file2.txt" | xargs touch     # create both files
cat urls.txt | xargs -n 1 curl -O            # download each URL, one at a time
```

> Why not just pipe directly? This does **NOT** work: `find . -name "*.tmp" | rm` — `rm` doesn't read stdin, it needs filenames as arguments, not piped text.

| Flag | Purpose |
|---|---|
| `-n N` | Pass only N arguments per command execution |
| `-I {}` | Placeholder for each item (needed when the item isn't the last argument) |
| `-P N` | Run N processes in parallel |
| `-0` | Use null-byte separation (pairs with `find -print0`, safest for filenames with spaces) |

```bash
# Unsafe - breaks on filenames with spaces
find . -name "*.log" | xargs rm

# Safe version
find . -name "*.log" -print0 | xargs -0 rm

# Using -I {} when the filename isn't the last argument
find . -name "*.jpg" | xargs -I {} cp {} /backup/
# {} is replaced by each filename in turn

# Real-world example - kill all processes matching a name
ps aux | grep node | awk '{print $2}' | xargs kill -9
```

### export — Set Environment Variables

`export` creates an environment variable and makes it available to programs started by the current shell.

```bash
export NAME="Hitesh"
export PATH="$PATH:/opt/myapp/bin"
export TERM=linux
```

### .bashrc vs .bash_profile vs .profile

The main difference is *when* they are executed, depending on login shell vs. interactive non-login shell.

| Shell Type | When It Happens | Startup File Read | Examples | Typical Use Cases |
|------------|-----------------|-------------------|-----------|-------------------|
| Login shell | Logging into a system for the first time | `.bash_profile` (or `.bash_login`, or `.profile` if neither exists) | SSH login, TTY login (`Ctrl+Alt+F3`), `su - user`, `sudo -i`, macOS Terminal (default) | Set environment variables (`PATH`, `JAVA_HOME`, `EDITOR`, `LANG`), then source `.bashrc` |
| Interactive non-login shell | Every new interactive Bash session after login | `.bashrc` | New Terminal window/tab, VS Code integrated terminal, GNOME Terminal, Konsole, running `bash` | Aliases, prompt (`PS1`), shell options (`shopt`), history settings, functions, tab completion |
| Non-interactive shell | Bash executes a script without user interaction | None (unless `BASH_ENV` is set) | `./script.sh`, `bash script.sh`, CI/CD pipelines, cron jobs | Scripts should define everything they need themselves |

| File | Executed When | Shell Specific | Common Contents | Should Contain |
|------|---------------|----------------|-----------------|----------------|
| `.bashrc` | Every interactive non-login Bash shell | Bash only | Aliases, functions, prompt, history settings, shell options, completion | Interactive customizations wanted in every terminal |
| `.bash_profile` | Login Bash shell only | Bash only | Environment variables, startup commands, login-specific init | `export` statements + sourcing `.bashrc` |
| `.profile` | Login shell if `.bash_profile`/`.bash_login` don't exist | POSIX-compliant shells (`sh`, `dash`, `bash`, `ksh`, etc.) | Generic environment variables, shell-independent settings | Portable login configuration |

```bash
# Typical flow when you SSH into a server:
# 1. Login shell starts -> reads ~/.bash_profile
# 2. ~/.bash_profile usually contains:
if [ -f ~/.bashrc ]; then
    source ~/.bashrc      # -> manually pulls in .bashrc too
fi
```

Common convention: put actual settings (aliases, `$PATH`, prompt, functions) in `.bashrc`; make `.bash_profile` just a redirect that sources `.bashrc`. `.profile` is the shell-agnostic fallback used by `sh`.

```bash
# Put permanent aliases, PATH changes, and prompt tweaks here:
nano ~/.bashrc

# Then reload without restarting the terminal:
source ~/.bashrc

# Quick way to check which one actually ran:
echo "bashrc loaded" >> ~/.bashrc
echo "bash_profile loaded" >> ~/.bash_profile
# open a new terminal and see which message(s) print
```

### stty — Control Terminal Settings

`stty` is used to display or modify terminal line settings and terminal characteristics.

```bash
stty size              # Show terminal rows and columns
stty rows 5            # Set terminal height to 5 rows
stty columns 80        # Set terminal width to 80 columns
stty -a                # Show all current terminal settings
```

### Getting Unstuck
When a command or program seems frozen or you're dropped into an unfamiliar screen:

| Situation | Fix |
|---------|-------------|
| Stuck inside less, man, or git log | Press q to quit |
| Command running forever / frozen terminal | Ctrl+C to interrupt/kill it |
| Accidentally paused a program | Ctrl+Z to suspend, then fg to resume it |
| Typed cat with no file, terminal waiting | Ctrl+D to send EOF and exit |
| Stuck inside vi/vim | Press Esc then type :q! and Enter |
| Terminal looks garbled/broken | Type reset and press Enter |

Rule of thumb: q for pagers/viewers, Ctrl+C for running commands, Ctrl+D for input prompts.

### screen / tmux — Persistent Terminal Sessions

Unlike `nohup`, these let you fully detach and reattach to a *live interactive* session later — essential when SSH connections drop.

```bash
# tmux (modern, more common)
tmux new -s mysession       # start a named session
tmux ls                     # list sessions
tmux attach -t mysession    # reattach
tmux kill-session -t mysession

# Inside tmux: Ctrl+B then D  -> detach (session keeps running)

# screen (older, still on many servers)
screen -S mysession         # start named session
screen -ls                  # list sessions
screen -r mysession         # reattach

# Inside screen: Ctrl+A then D  -> detach
```
> Interview one-liner: `nohup cmd &` survives logout but you can't reattach to interact with it; `tmux`/`screen` give you a persistent *interactive* session you can detach and reattach to.

---

## File & Directory Commands

### ls — List Files and Directories

```bash
ls [OPTIONS] [FILE/DIRECTORY]
```

| Command | Description |
|---------|-------------|
| `ls` | Lists files in current directory (names only) |
| `ls -l` | Long listing format — permissions, ownership, size, modified time |
| `ls -a` | Shows all files including hidden ones (files starting with `.`) |
| `ls -la` / `ls -lah` | Combines long format + hidden files (+ human-readable sizes) |
| `ls -lh` | Long format with human-readable file sizes (KB, MB, GB) |
| `ls -lt` | Long format sorted by modification time (newest first) |
| `ls -R` | Recursively lists all files in subdirectories too |

Example output of `ls -l`:
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

```bash
$ ls -a
.  ..  .bashrc  .profile  script.sh  projects
```
`.bashrc` and `.profile` are hidden config files — they start with a dot (`.`).

**Interview Q&A**
- *Difference between `ls` and `ls -l`?* `ls` only shows names. `ls -l` shows detailed information.
- *What does `ls -a` show?* Hidden files starting with `.`.

> **Color cheat sheet (default terminal colors):** blue = directory · green = executable file · white/default = regular file · cyan = symbolic link · red = archive (.tar, .zip) · yellow/black-on-yellow = device file.

### tree — Visualize Directory Structure

```bash
tree                    # Show folder structure as a tree (may need: apt install tree)
tree -L 2               # Limit depth to 2 levels
tree -a                 # Include hidden files
tree -d                 # Directories only, no files
```

### Filenames with Spaces

Linux allows spaces in filenames, but the shell treats spaces as argument separators — so unquoted filenames with spaces get split incorrectly.
```bash
touch "my file.txt"      # creates one file: "my file.txt"

cd my file                # ERROR: shell thinks these are two arguments ("my" and "file")
cd "my file"               # correct
cd my\ file                 # also correct (escaped space)

rm my file.txt              # DANGEROUS: tries to remove two files "my" and "file.txt"
rm "my file.txt"             # correct
```

### cat — View / Access Files

```bash
cat -- "--spaces in this filename--"   # View file --spaces in this filename--
cat ./-file07                          # View file -file07 (without "./" it errors)
cat notes.txt                          # Display file
cat > file.txt                         # Create file: type content, then Ctrl+D
cat file1 file2 > combined.txt         # Merge files
cat -n file.txt                        # Number lines
```
> *cat vs less?* `cat` prints everything. `less` shows one page at a time.

### less — Page Through Large Files

```bash
less server.log
```
Navigation: `Up`/`Down` arrows, `Space`/`Page Down`, `Page Up`, `/` search, `q` quit.
> Why use `less`? Large log files — doesn't load the whole file into memory.

### more — Page Through Files

`more` is a pager that displays text one screen at a time.

```bash
more filename.txt
```
Useful keyboard commands:
Space       → Next page
Enter       → Next line
b           → Previous page (on supported versions)
q           → Quit
v           → Open the current file in an editor

| Feature              | `more`                    | `less` |
| -------------------- | ------------------------- | ------ |
| Page through files   | Yes                       | Yes    |
| Search               | Limited                   | Yes    |
| Move backward        | Limited/version-dependent | Yes    |
| Large log files      | Yes                       | Yes    |
| Common modern choice | Less common               | `less` |

### diff — Compare Files

`diff` compares two files and shows the differences between them. It is commonly used to compare configuration files, source code, backups, or old and new versions of a file.

```bash
diff file1.txt file2.txt
```

Example:

```bash
diff old.conf new.conf
```

By default, `diff` displays the differences in a compact format.

#### Useful Options

```bash
diff -u old.conf new.conf       # Unified format — easier for humans to read
diff -c old.conf new.conf       # Context format
diff -q old.conf new.conf       # Only report whether files differ
diff -i old.conf new.conf       # Ignore case differences
diff -w old.conf new.conf       # Ignore whitespace differences
diff -r dir1 dir2               # Compare directories recursively
```

#### Unified Diff Format

```bash
diff -u old.txt new.txt
```

Typical output:

```text
--- old.txt
+++ new.txt
@@
-Hello
+Hello Linux
```

Meaning:

```text
-   # Line exists in the first file but not the second
+   # Line exists in the second file but not the first
```

#### Compare Sorted Data

`diff` can also compare command output:

```bash
diff <(sort file1.txt) <(sort file2.txt)
```

This compares the sorted contents without creating temporary files.

#### Check Whether Two Files Are Identical

```bash
diff -q file1.txt file2.txt
```

Example:

```text
Files file1.txt and file2.txt differ
```

> `diff` compares contents. It does not merge the files or modify either input file.


### cp — Copy Files and Directories

```bash
cp [OPTIONS] SOURCE DESTINATION

cp file.txt backup.txt      # Copy file
cp -r project backup/       # Copy directory (recursive; without -r: "omitting directory")
cp -p file.txt backup.txt   # Preserve ownership, timestamps, permissions
cp -i file.txt backup.txt   # Interactive: asks "overwrite?" before replacing an existing file
cp -v file.txt backup.txt   # Verbose: 'file.txt' -> 'backup.txt'
cp report{,.bak}            # expands to: cp report report.bak
cp -a project backup/       # Archive mode: recursive + preserves permissions/timestamps/links (shortcut for -dR --preserve=all)
```
> Why is `-r` required? Directories contain subdirectories/files — recursive mode copies everything.

### mv — Move or Rename

```bash
mv SOURCE DESTINATION

mv old.txt new.txt                          # Rename file
mv report.pdf /home/user/Documents/         # Move file
mv *.txt backup/                            # Move multiple files
mv project old_project                      # Rename directory
mv file?.txt archive/                       # only single-char-suffix files
mv -i old.txt new.txt       # Interactive: asks before overwriting an existing destination file
```

### rm / rmdir — Remove Files & Directories

```bash
rm [OPTIONS] FILE

rm notes.txt              # Delete file
rm -r folder/             # Delete directory
rm -f file.txt            # Force delete, no confirmation
rm -rf directory/         # Recursive + force — permanently deletes, no recycle bin
rm -ri folder             # Safe alternative: asks before deletion
rm backup_*.tar.gz        # delete all matching backups (glob)
```
| Option | Description |
|----------|-------------|
| `-r` | Recursive |
| `-f` | Force delete |

```bash
rmdir empty_folder          # removes directory only if it's empty
rmdir -p a/b/c              # removes nested empty directories
# For non-empty directories, use rm -r instead
```
> Why is `rm -rf` dangerous? It permanently deletes files without confirmation.

### mkdir / mktemp — Create Directories

```bash
mkdir directory_name          # Create single directory
mkdir dir1 dir2 dir3          # Create multiple directories
mkdir -p project/src/java     # Create nested directories (creates parent dirs automatically)

mktemp -d                     # Create temporary directory
cd /tmp/tmp.r4mK9sL1Qa
```
> Without `-p`: `No such file or directory`.

### touch — Create Empty Files / Update Timestamps

```bash
touch filename
touch notes.txt              # Create empty file
touch a.txt b.txt c.txt      # Create multiple files
touch existing.txt           # Update modification time (doesn't overwrite content)
```

### file / find — Identify & Locate Files

```bash
file ./*                              # Shows types like data, ASCII text, Key
find [path] [options] [expression]

# Find by name
find / -name "file.txt"               # Find anywhere on system
find /home -name "*.sh"               # Find all shell scripts
find /var -name "*.log"               # Find all log files
find . -name "config*"                # Find files starting with config
find . -iname "readme*"               # Case-insensitive name search (matches README, ReadMe, readme...)

# Find by type
find /tmp -type f                     # Files only
find /home -type d                    # Directories only
find / -type l                        # Symbolic links only

# Find by size
find /var -size +10M                  # Files larger than 10MB
find /home -size -1k                  # Files smaller than 1KB
find / -size +100M -size -1G          # Between 100MB and 1GB

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
find /tmp -name "*.tmp" -delete            # Delete all .tmp files
find /logs -name "*.log" -exec cat {} \;   # Cat each found file
find /home -type f -exec chmod 644 {} \;   # Fix permissions

# Other examples
find . -type f -size 1033c ! -executable                  # human-readable, 1033 bytes, not executable
find / -type f -user bandit7 -group bandit6 -size 33c 2>/dev/null
```

### stat — Detailed File Information

```bash
stat file.txt
# Shows size, permissions, owner, inode, and access/modify/change timestamps
# More detail than `ls -l` — useful for checking exactly when a file changed
```

### basename / dirname — Split a Path

```bash
basename /home/user/project/app.sh    # app.sh (just the filename)
basename /home/user/project/          # project (last folder name)
dirname /home/user/project/app.sh     # /home/user/project (path without filename)
```
> Commonly used inside scripts to build filenames or figure out a script's own directory:
```bash
SCRIPT_DIR=$(dirname "$0")
```

### realpath — Resolve the Full Absolute Path

```bash
realpath ../notes.txt        # /home/user/notes.txt
realpath ./script.sh         # turns a relative path into an absolute one
```

### Soft Link (Symbolic) vs Hard Link — See [Links](#links-soft-vs-hard)

---

## Permissions & Ownership

### chmod — Change Mode

`chmod` modifies read, write, and execute permissions for files and directories.

| Symbol | Octal | Meaning |
|--------|-------|---------|
| `r` | 4 | Read |
| `w` | 2 | Write |
| `x` | 1 | Execute |
| `-` | 0 | No permission |

| Octal | Symbolic | Meaning |
|-------|----------|---------|
| `755` | `rwxr-xr-x` | Owner: full, Group+Others: read+execute |
| `644` | `rw-r--r--` | Owner: read+write, Group+Others: read only |
| `700` | `rwx------` | Owner: full, Group+Others: no access |
| `777` | `rwxrwxrwx` | Everyone: full access (avoid in production!) |

```bash
# Numeric method
chmod 755 script.sh       # Owner: rwx, Group: r-x, Others: r-x
chmod 644 config.txt      # Owner: rw-, Group: r--, Others: r--
chmod 700 private.sh      # Only owner can read, write, execute

# Symbolic — Add Permissions (+)
chmod u+x script.sh           # Add execute permission for owner
chmod u+w notes.txt           # Add write permission for owner
chmod g+w project.txt         # Add write permission for group
chmod g+x deploy.sh           # Add execute permission for group
chmod o+r file.txt            # Add read permission for others
chmod o+x script.sh           # Add execute permission for others
chmod a+x script.sh           # Add execute permission for everyone
chmod a+r file.txt            # Add read permission for everyone
chmod ug+w shared.txt         # Add write permission to owner and group
chmod go+r document.txt       # Add read permission to group and others

# Symbolic — Remove Permissions (-)
chmod u-w file.txt            # Remove write permission from owner
chmod u-x script.sh           # Remove execute permission from owner
chmod g-w project.txt         # Remove write permission from group
chmod g-x deploy.sh           # Remove execute permission from group
chmod o-r secret.txt          # Remove read permission from others
chmod o-w public.txt          # Remove write permission from others
chmod a-x script.sh           # Remove execute permission from everyone
chmod a-w readonly.txt        # Remove write permission from everyone

# Symbolic — Set Exact Permissions (=)
chmod u=rwx file.sh           # Owner: read, write, execute
chmod u=rw file.txt           # Owner: read and write only
chmod g=rx script.sh          # Group: read and execute only
chmod g=r file.txt            # Group: read only
chmod o=r file.txt            # Others: read only
chmod o= file.txt             # Remove all permissions from others
chmod a=r file.txt            # Everyone: read only
chmod u=rwx,g=rx,o=r file.sh  # Set exact permissions for all

# Multiple Operations
chmod u+x,g-w,o-r file.txt    # Add execute to owner, remove write from group, remove read from others
chmod ug+rwx,o= file.sh       # Owner & group: full access, others: no access
chmod u=rw,g=r,o= file.txt    # Equivalent to chmod 640
chmod u=rwx,g=rx,o=rx app.sh  # Equivalent to chmod 755
chmod u=rwx,g=rwx,o=rx app.sh # Equivalent to chmod 775
chmod a=rw file.txt           # Everyone: read and write
chmod a=r file.txt            # Everyone: read only

# Recursive
chmod -R u+rwx project/       # Give owner full permissions recursively
chmod -R g+rw shared/         # Give group read and write recursively
chmod -R o-r private/         # Remove read permission for others recursively
chmod -R a+X scripts/         # Add execute only to directories and executable files
chmod -R 755 /var/www/html    # Apply to directory and all contents
```

> Interview tip: `755` is common for scripts/directories; `644` is standard for regular files.

### chown / chgrp — Change Ownership

Every file has an owner (user) and a group. `chmod` controls WHAT each can do (r/w/x). `chown`/`chgrp` control WHO the owner/group actually are.

```bash
chown hitesh file.txt         # change owner
chown hitesh:devops file.txt  # change owner AND group
chgrp devops file.txt         # change group only
chown -R hitesh:devops dir/   # recursive
```

### umask

`umask` sets the default permissions removed when new files/directories are created.

```bash
umask            # show current umask, e.g. 0022

# Default max permissions:
# Files: 666 (rw-rw-rw-)
# Directories: 777 (rwxrwxrwx)
# umask 022 subtracts: files become 644, dirs become 755

umask 027         # more restrictive default
umask 0022        # typical default
```

### Symbolic Permission Format

```text
-rwxr-xr--
File type: - (file), d (dir), l (link), c (char), b (block)
Owner (user):   rwx  = 7
Group:          r-x  = 5
Others (world): r--  = 4
```

| Character | Meaning |
|-----------|---------|
| `-` | Regular file |
| `d` | Directory |
| `l` | Symbolic link |
| `c` | Character device |
| `b` | Block device |
| `p` | Named pipe |
| `s` | Socket |

### What r, w, x Actually Mean on a Directory

Permissions behave differently on directories than on files — a very common beginner confusion:

| Permission | On a File | On a Directory |
|-----------|-----------|-----------------|
| `r` | Read file contents | List filenames inside (`ls`) |
| `w` | Modify file contents | Create/delete/rename files inside |
| `x` | Execute the file as a program | "Enter" the directory (`cd`) and access items inside |

```bash
# You can "cd" into a folder you can't "ls" if you have x but not r
chmod 711 folder/    # owner: full, group/others: execute only (traverse but not list)

# You need x on EVERY parent directory in a path to access a file deep inside it
# e.g. to read /a/b/c.txt you need x on /a and /a/b, plus r on c.txt
```

### Special Permissions

```bash
# SUID (Set User ID) - runs as file owner, not current user
chmod u+s /usr/bin/passwd
# Shows as: -rwsr-xr-x

# SGID (Set Group ID) - files inherit group of directory
chmod g+s /shared/folder
# Shows as: drwxr-sr-x

# Sticky Bit - only owner can delete their own files
chmod +t /tmp
# Shows as: drwxrwxrwt

# Same permissions, numeric (4-digit) form — leading digit: 4=SUID, 2=SGID, 1=Sticky
chmod 4755 /usr/bin/passwd     # SUID + rwxr-xr-x
chmod 2775 /shared/folder      # SGID + rwxrwxr-x
chmod 1777 /tmp                # Sticky + rwxrwxrwx
```

---

## Users, Groups & Access

### What Is Root?
Every Linux system has one special account called **root** (UID `0`). Root bypasses all permission checks — it can read, write, or delete any file, and run any command, regardless of ownership.
- Normal users can only affect files they own (or have been granted access to)
- Root can affect anything, which is powerful but dangerous — a typo as root can break the whole system
- `sudo` lets a permitted user run a single command as root without switching accounts; `su`/`sudo -i` switch to being root fully
- Rule of thumb: use `sudo` for a single command, avoid staying logged in as root longer than necessary

### User Management

```bash
# Add user
useradd hitesh                         # Create user
useradd -m -s /bin/bash hitesh         # With home dir and bash shell
passwd                                 # Change YOUR OWN password (no username needed — most common everyday use)
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

### Group Management

```bash
groupadd developers              # create a new group
groupdel developers              # delete a group
groupmod -n newname oldname      # rename a group
gpasswd -a hitesh developers     # add existing user to a group
```

### /etc/passwd, /etc/shadow, /etc/group

```text
/etc/passwd - one line per user, colon-separated:
username:x:UID:GID:comment:home_dir:shell

/etc/shadow - stores hashed passwords (root-only readable):
username:hashed_password:last_changed:min:max:warn

/etc/group - one line per group:
groupname:x:GID:member1,member2
```

```bash
cat /etc/passwd | grep hitesh
cat /etc/group | grep sudo
sudo cat /etc/shadow

passwd hitesh          # set/change password for user hitesh
passwd -l hitesh       # lock account (disable login)
passwd -u hitesh       # unlock account
chage -l hitesh        # show password expiry info
chage -M 90 hitesh     # force password change every 90 days
```

### /etc/shells & /etc/gshadow

`/etc/shells` and `/etc/gshadow` are important system files related to user accounts, login shells, and groups.

#### `/etc/shells` — Valid Login Shells

`/etc/shells` contains a list of shells that are considered valid login shells on the system. Programs such as `chsh` can use this list when changing a user's login shell.

```bash
cat /etc/shells
```

Example:

```text
/bin/sh
/bin/bash
/bin/dash
/bin/zsh
```

Useful searches:

```bash
grep -i "bash" /etc/shells       # Check whether Bash is listed
grep -i "zsh" /etc/shells        # Check whether Zsh is listed
```

> `/etc/shells` is a list of allowed shell paths; it is not the file that stores which shell a particular user currently uses. A user's configured login shell is stored in the final field of `/etc/passwd`.

#### `/etc/gshadow` — Secure Group Information

`/etc/gshadow` stores protected group information. It is similar to `/etc/group`, but contains security-sensitive group password and administrator/member information.

```bash
sudo cat /etc/gshadow
```

A typical entry has the general format:

```text
group:group_password:group_admins:group_members
```

For example:

```text
developers:!:alice:bob,charlie
```

Fields:

```text
group             # Group name
group_password    # Group password field
group_admins      # Users who can administer the group
group_members     # Users who belong to the group
```

> `/etc/gshadow` contains security-sensitive information and is normally readable only by root. Do not post its contents publicly or include real system secrets in screenshots.

#### Compare the Four Common Account Files

| File           | Purpose                                                        |
| -------------- | -------------------------------------------------------------- |
| `/etc/passwd`  | Basic user account information                                 |
| `/etc/shadow`  | Password hashes and password-aging information                 |
| `/etc/group`   | Group names, GIDs, and group members                           |
| `/etc/gshadow` | Protected group passwords and group administration information |


### /etc/services & /etc/nsswitch.conf

```text
/etc/services - maps service names to port numbers/protocols, used by networking tools:
http    80/tcp
https   443/tcp
ssh     22/tcp

/etc/nsswitch.conf - tells the system WHERE to look up things like hostnames, users, and passwords, and in what order:
hosts:    files dns        # check /etc/hosts first, then DNS
passwd:   files            # check /etc/passwd
```

```bash
cat /etc/services | grep ssh      # look up a service's default port
cat /etc/nsswitch.conf            # view name resolution order
```

### su vs sudo -i

```bash
su username        # switch user, needs THEIR password, keeps some of your env
su - username       # switch user with full login environment (like a fresh login)
sudo -i             # switch to root using YOUR password, full root login environment
sudo -s             # switch to root shell but keep current environment
```
**Interview Q&A:** *What's the core difference between `su` and `sudo`?*
`su` switches you to another user's full session and requires **that user's password**. `sudo` runs a **single command as root** (or another user) using **your own password**, then returns you to your normal session — making it safer, more auditable (logged per-command), and more granular (admins can restrict exactly which commands a user may run via `/etc/sudoers`).

### who, w, last, lastlog

```bash
who              # who is currently logged in
w                # who is logged in + what they're doing
last             # history of past logins
lastlog          # last login time for each user
```

### sudo — Superuser Do

Allows a permitted user to run commands as root without fully switching to the root account.
- Safer — limits damage from mistakes
- Auditable — all `sudo` commands are logged in `/var/log/auth.log`
- Granular — control which commands each user can run

```bash
sudo apt update               # Update package list (requires root)
sudo systemctl restart nginx  # Restart service
sudo nano /etc/hosts          # Edit protected system file
sudo -i                       # Switch to root shell (interactive)
sudo -u postgres psql         # Run command as specific user (postgres)
sudo !!                       # Re-run last command with sudo

# Grant sudo access
usermod -aG sudo hitesh       # Ubuntu/Debian: add user to sudo group
usermod -aG wheel hitesh      # RHEL/CentOS: add user to wheel group

# Check sudo privileges
sudo -l          # List what the current user can run with sudo
```

### SSH

```bash
ssh -p port_number username@hostname
ssh -p port_number username@hostname cat readme

# Generate Key
ssh-keygen

# Connect using ssh key
vi sshkey.private
-----BEGIN OPENSSH PRIVATE KEY-----
#SDALSNDLKASNDANSLJND...
-----END OPENSSH PRIVATE KEY-----

chmod 600 sshkey.private
ssh -i sshkey.private -p port_number username@hostname
```

---

## Searching & Text Processing

### head / tail — Beginning / End of a File

```bash
head filename.txt          # Shows first 10 lines (default)
head -n 20 filename.txt    # Shows first 20 lines (POSIX-portable form)
head -5 filename.txt       # Shows first 5 lines

tail filename.txt          # Shows last 10 lines (default)
tail -n 20 filename.txt    # Shows last 20 lines
tail -f /var/log/syslog    # Follow mode: real-time log monitoring
tail -F /var/log/app.log   # Follow mode + retry if file is recreated
```

Practical use:
```bash
# Watch nginx access log live
tail -f /var/log/nginx/access.log

# Watch last 50 lines + follow
tail -n 50 -f /var/log/syslog

# Combine head and tail to view middle of file (lines 20-30)
head -30 file.txt | tail -11
```

### grep — Global Regular Expression Print

```bash
grep "pattern" filename
grep "pattern" file1 file2     # Search in multiple files
grep "pattern" *.log           # Search in all .log files
```

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

```bash
# Basic search
grep "error" app.log               # Search for "error"
grep -i "error" app.log            # Case-insensitive search

# Recursive search
grep -r "password" /etc            # Search recursively
grep -rn "TODO" .                  # Recursive search with line numbers

# Match options
grep -v "INFO" app.log             # Show lines NOT containing INFO
grep -w "cat" file.txt             # Match whole word only
grep -x "Completed" status.txt     # Match entire line only

# Line numbers and counting
grep -n "main" program.c           # Show line numbers
grep -c "error" app.log            # Count matching lines

# Multiple patterns
grep -E "error|warning" app.log    # Match either "error" or "warning"

# Show context around matches
grep -A 3 "Exception" app.log      # 3 lines after match
grep -B 3 "Exception" app.log      # 3 lines before match
grep -C 3 "Exception" app.log      # 3 lines before & after

# Show matching filenames
grep -l "TODO" *.py                # Files containing TODO

# Highlight matches
grep --color=auto "error" app.log
```

Using grep with other commands:
```bash
ps -ef | grep nginx                # Find running process
history | grep docker              # Search command history
env | grep JAVA                    # Find environment variables
ss -tuln | grep 443                # Check if port 443 is open
ls -l | grep ".txt"                # Filter files by extension
cat /etc/passwd | grep root        # Find root user entry
```

Common regex examples:
```bash
grep "^root" /etc/passwd           # Starts with "root"
grep "bash$" /etc/passwd           # Ends with "bash"
grep "^$" file.txt                 # Empty lines
grep "[0-9]" file.txt              # Contains a digit
grep "[A-Z]" file.txt              # Contains uppercase letters
grep -E "colou?r" file.txt         # Match "color" or "colour"
```

### wc — Word Count

```bash
wc [OPTIONS] file

wc -l file.txt   # Count lines
wc -w file.txt   # Count words
wc -m file.txt   # Count characters
wc -c file.txt   # Count bytes
```
> *What does `wc -l` return?* Total number of lines.

### sort / uniq

```bash
sort file.txt        # Alphabetical sort
sort -r names.txt     # Reverse
sort -n numbers.txt   # Numeric
sort -u file.txt      # Remove duplicates
```
> *sort vs sort -n?* `sort` is alphabetical, `sort -n` is numeric.

```bash
uniq file.txt         # Removes adjacent duplicate lines
uniq -c file.txt       # Count duplicates
uniq -u file.txt       # Remove non-unique lines

# Usually used with sort, since uniq only removes ADJACENT duplicates:
sort file.txt | uniq
```

Example:
```text
Input:              Output (uniq):        Output (uniq -c):
apple                apple                 2 apple
apple                banana                2 banana
banana               orange                1 orange
banana
orange
```

### cut

```bash
cut [OPTIONS] file

cut -d: -f1 /etc/passwd    # Extract first field (delimiter ":")
cut -d, -f2 employee.csv   # CSV example: extract 2nd field
```
| Option | Meaning |
|----------|----------|
| `-d` | Delimiter |
| `-f` | Field |

### awk

Powerful text-processing language.

```bash
awk '{print $1}' file.txt          # Print first column
awk '{print $1,$2}'                # Print multiple columns
awk '{print $NF}'                  # Print last column (NF = Number of Fields)
awk '{sum+=$2} END {print sum}'    # Sum numbers
awk '$3>100'                       # Filter
```
> *Why is awk powerful?* It can filter, calculate, format, search, parse, and generate reports.

### sed — Stream Editor

```bash
sed 's/old/new/' file.txt          # Replace first occurrence per line
sed 's/old/new/g' file.txt         # Replace all (g = Global)
sed -i 's/old/new/g' file.txt      # Edit file directly
sed '3d' file.txt                  # Delete line 3
sed -n '5p' file.txt               # Print only line 5
sed 's/[0-9]/X/g'                  # Replace using regex
```

*sed vs awk:*

| sed | awk |
|------|------|
| Stream editor | Programming language |
| Best for replacing text | Best for parsing structured data |
| Line-oriented editing | Field-oriented processing |
| Supports regex | Supports variables, conditions, loops, arithmetic |

### tr — Translate Characters

```bash
echo "abc" | tr 'abc' 'xyz'                        # xyz
cat data.txt | tr 'A-Za-z' 'N-ZA-Mn-za-m'          # Alphabet rotated by 13 positions
tr 'A-Za-z' 'N-ZA-Mn-za-m' < data.txt
```

### strings

Extracts printable strings from binary files.

```bash
strings data.txt | grep "==="        # Shows human-readable strings preceded by several '=' characters
```

### Common Command Combinations

```bash
# Find duplicate usernames
cut -d: -f1 /etc/passwd | sort | uniq

# Count unique entries
sort file.txt | uniq | wc -l

# Replace text and save
sed 's/Linux/Ubuntu/g' input.txt > output.txt

# Print first column then sort
awk '{print $1}' employees.txt | sort

# Count occurrences
sort file.txt | uniq -c

# Find top 10 IPs with failed SSH attempts
cat /var/log/auth.log | grep "Failed" | awk '{print $11}' | sort | uniq -c | sort -rn | head -10
```

### Real-World Text-Processing Examples

```bash
cp -r myproject/ backup/                       # Backup a project
mv app.log app.log.old                         # Rename a log file
rm -rf /tmp/project/*                          # Delete temporary files
less /var/log/syslog                           # View a large log file
awk '{print $1}' access.log | sort | uniq      # Find unique IP addresses in a log
sed -i 's/http:/https:/g' config.conf          # Replace "http" with "https" in a config file
```

---

## Networking

```bash
# Basic connectivity test
ping google.com             # Send ICMP packets continuously
ping -c 4 google.com        # Send only 4 packets
ping -i 2 google.com        # Interval 2 seconds between pings

# IP configuration
ip addr show                # Show all network interfaces and IPs
ip addr show eth0           # Show specific interface
ip link show                # Show network interfaces and status
hostname -I                 # Display all assigned IP addresses
hostname -i                 # Display host IP address
ifconfig                    # Older alternative (may need net-tools) — deprecated, ip addr preferred

# Routing
ip route show               # Show routing table
route -n                    # Show routing table (numeric)
traceroute google.com       # Show packet path to destination
tracepath google.com        # Similar to traceroute

# Port and connection monitoring
ss -tulnp                   # Show listening ports (modern)
ss -s                       # Summary statistics
ss -tp                      # TCP connections with process names
ss -tun                     # Show all TCP/UDP connections
netstat -tulnp              # Show listening ports (older)
netstat -rn                 # Show routing table
netstat -i                  # Show network interface statistics

# DNS lookup
nslookup google.com         # DNS query
dig google.com              # Detailed DNS query
dig google.com +short       # Show only the IP address
host google.com             # Simple DNS lookup
cat /etc/resolv.conf        # View configured DNS servers

# Test specific ports
nc -zv google.com 443                          # Check if TCP port 443 is open

# Send data to a port
echo "password" | nc -l 12345    # Listen on a port
./suconnect 12345    # On another Terminal

telnet google.com 80                           # Test TCP connection (if installed)
nmap localhost -p 31000-32000                  # Find open ports within a range
cat /etc/bandit_pass/bandit14 | nc localhost 30000   # Submit password to port 30000 on localhost
cat /etc/bandit_pass/bandit15 | openssl s_client -connect localhost:30001 -quiet   # Submit password over SSL/TLS
```

| Part | Meaning |
| ----------- | ------------------------- |
| `openssl` | OpenSSL command-line tool |
| `s_client` | SSL/TLS client |
| `-connect` | Connect to a server |
| `localhost` | This machine |
| `30001` | Server port |
| `-quiet` | reduce/suppress extra TLS connection information |

```bash
# Download a webpage (test HTTP/HTTPS)
curl https://google.com     # Fetch webpage
curl -I https://google.com  # Show only HTTP headers
wget https://example.com    # Download a file

# ARP (Address Resolution Protocol)
arp -a                      # Show ARP cache
ip neigh                    # Modern replacement for arp

# Network interface statistics
ip -s link show eth0        # Packet statistics
ip -br addr                 # Brief IP address summary
ethtool eth0                # Display NIC speed, duplex, driver info

# Socket and process information
lsof -i                     # List processes using network
lsof -i :80                 # Processes using port 80
fuser 8080/tcp               # Process using TCP port 8080

# Firewall
iptables -L                 # List iptables firewall rules
firewall-cmd --list-all     # Show firewalld configuration (RHEL/CentOS)
ufw status                  # Show UFW firewall status (Ubuntu)

# Network services
systemctl status NetworkManager    # Check NetworkManager
systemctl status networking        # Check networking service (Debian/Ubuntu)

# View hosts configuration
cat /etc/hosts                     # Local hostname mappings
hostname                           # Display hostname
hostnamectl                        # Show hostname and system information
hostnamectl set-hostname newname   # Change system hostname permanently

# Live network monitoring
watch -n 1 ss -tuln         # Refresh listening ports every second
watch -n 2 ip addr          # Watch IP address changes
```
### curl — Transfer Data from URLs

`curl` is a command-line tool for transferring data to or from URLs. It is commonly used for HTTP/HTTPS requests, APIs, downloading content, and testing web services.

```bash
curl https://example.com             # Fetch a webpage
curl -I https://example.com          # Show HTTP response headers only
curl -o page.html https://example.com # Save output to a specific filename
curl -O https://example.com/file.txt  # Save using the remote filename
```

#### Common Options

```bash
curl -I https://example.com
```

`-I` requests headers only.

```bash
curl -L https://example.com
```

`-L` follows HTTP redirects.

```bash
curl -o output.html https://example.com
```

`-o` writes the response body to the specified filename.

```bash
curl -O https://example.com/file.txt
```

`-O` saves the file using its remote filename.

```bash
curl -s https://example.com
```

`-s` runs silently and suppresses the progress meter.

```bash
curl -v https://example.com
```

`-v` displays detailed request and connection information, useful for troubleshooting.

#### API Example

```bash
curl -H "Content-Type: application/json" https://api.example.com/users
```

`-H` adds an HTTP request header.

> `curl` is especially useful when you need to inspect HTTP requests, response headers, APIs, or troubleshoot connectivity.

### wget — Download Files

`wget` is primarily used to download files from HTTP, HTTPS, and other supported protocols.

```bash
wget https://example.com/file.tar.gz
```

This downloads the file to the current directory.

#### Common Options

```bash
wget -O output.tar.gz https://example.com/file.tar.gz
```

`-O` saves the download using the specified filename.

```bash
wget -c https://example.com/large.iso
```

`-c` resumes a partially completed download.

```bash
wget -q https://example.com/file.txt
```

`-q` runs quietly.

```bash
wget -P /tmp https://example.com/file.txt
```

`-P` specifies the directory in which to save the downloaded file.

#### curl vs wget

| Feature               | `curl`          | `wget`                |
| --------------------- | --------------- | --------------------- |
| HTTP requests/APIs    | Excellent       | More download-focused |
| Download files        | Yes             | Yes                   |
| Resume downloads      | Yes             | Yes                   |
| Inspect headers       | Very convenient | More limited          |
| Recursive downloading | No              | Yes                   |

> Use `curl` when working with HTTP requests and APIs; use `wget` when the main task is downloading files or recursively retrieving web content.

### dig — DNS Lookup

`dig` (Domain Information Groper) is a command-line DNS troubleshooting and lookup tool. It queries DNS servers and displays detailed information about DNS records.

```bash
dig example.com
```

This performs a DNS lookup and displays the DNS response.

#### Common Queries

```bash
dig example.com +short
```

Show only the concise answer, such as an IP address.

```bash
dig example.com A
```

Query the IPv4 `A` record.

```bash
dig example.com AAAA
```

Query the IPv6 `AAAA` record.

```bash
dig example.com MX
```

Query mail-server (`MX`) records.

```bash
dig example.com NS
```

Query authoritative name-server (`NS`) records.

```bash
dig example.com TXT
```

Query `TXT` records.

#### Query a Specific DNS Server

```bash
dig @8.8.8.8 example.com
```

This sends the DNS query to the specified DNS server.

#### Reverse DNS Lookup

```bash
dig -x 8.8.8.8
```

Attempts to find the hostname associated with an IP address.

#### Useful Options

```bash
dig +short example.com       # Concise answer
dig +trace example.com       # Trace DNS resolution from the root
dig +stats example.com       # Show query statistics
```

> `dig` is primarily a DNS diagnostic tool. For a quick basic lookup, `host` or `nslookup` may produce simpler output.

### Firewall (ufw / iptables)

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

### ifconfig vs ip addr

```bash
ifconfig  -> legacy command (net-tools package), still works on many systems but deprecated
ip addr   -> modern replacement (iproute2 package), preferred on current distros

ifconfig eth0            # old way to view interface info
ip addr show eth0        # modern equivalent
```

### File Transfer (`scp` / `rsync`)

#### scp — Secure Copy

`scp` copies files between machines over SSH. It is useful for straightforward file transfers when an SSH connection is available.

```bash
scp file.txt user@server:/path/
```

Copy a remote file to the local machine:

```bash
scp user@server:/path/file.txt .
```

Copy a directory recursively:

```bash
scp -r folder/ user@server:/path/
```

Use a custom SSH port:

```bash
scp -P 2222 file.txt user@server:/path/
```

Use a specific SSH private key:

```bash
scp -i ~/.ssh/id_ed25519 file.txt user@server:/path/
```

#### Important `scp` Options

| Option | Purpose                                    |
| ------ | ------------------------------------------ |
| `-r`   | Copy directories recursively               |
| `-P`   | Specify SSH port                           |
| `-i`   | Use a specific private key                 |
| `-p`   | Preserve file modification times and modes |
| `-q`   | Suppress progress information              |

#### rsync — Synchronize Files

`rsync` synchronizes files and directories between locations. It is especially useful for backups and repeated transfers because it can transfer only the changes that are needed.

```bash
rsync -av source/ user@server:/destination/
```

Common options:

```bash
rsync -a source/ destination/
```

`-a` enables archive mode, preserving important file attributes and recursively copying directories.

```bash
rsync -v source/ destination/
```

`-v` shows what is being transferred.

```bash
rsync -z source/ user@server:/destination/
```

`-z` compresses data during transfer.

```bash
rsync -n -av source/ destination/
```

`-n` performs a dry run — it shows what would happen without actually changing the destination.

```bash
rsync -av --delete source/ destination/
```

`--delete` removes destination files that no longer exist in the source.

> `--delete` is powerful and potentially destructive. Use a dry run first:
>
> ```bash
> rsync -avn --delete source/ destination/
> ```

#### scp vs rsync

| Feature                     | `scp` | `rsync`   |
| --------------------------- | ----- | --------- |
| Simple file copy            | Yes   | Yes       |
| Directory transfer          | Yes   | Yes       |
| Incremental synchronization | No    | Yes       |
| Dry run                     | No    | Yes       |
| Efficient repeated backups  | Basic | Excellent |
| SSH support                 | Yes   | Yes       |

> Use `scp` for a simple one-time copy. Use `rsync` when repeatedly synchronizing directories or creating backups.

---

## Archives & Compression

### tar — Tape Archive

Bundles multiple files into a single archive (and optionally compresses it).

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

### zip / unzip

```bash
zip archive.zip file1.txt file2.txt      # create zip
zip -r archive.zip folder/               # zip a directory recursively
unzip archive.zip                        # extract
unzip -l archive.zip                     # list contents without extracting
unzip archive.zip -d /target/dir/        # extract to specific directory
```

### gunzip / bunzip2

- **gunzip**: decompresses Gzip (`.gz`) files, compressed with `gzip`
- **bunzip2**: decompresses Bzip2 (`.bz2`) files, compressed with `bzip2`

```bash
mv data data.gz
gunzip data.gz

mv data data.bz2
bunzip2 data.bz2
```

Check the file type first to know which to use:
```bash
file data
# data: gzip compressed data     -> use gunzip data.gz
# data: bzip2 compressed data    -> use bunzip2 data.bz2
```

| Command | File Extension | Used For |
| --------- | -------------- | ---------------------- |
| `gunzip` | `.gz` | Gzip-compressed files |
| `bunzip2` | `.bz2` | Bzip2-compressed files |

---

## Package Management

`apt` and `yum`/`dnf` install, update, and remove software on Linux.

| Feature | `apt` | `yum` / `dnf` |
|---------|-------|---------------|
| Distribution | Debian, Ubuntu | RHEL, CentOS, Fedora |
| Package format | `.deb` | `.rpm` |
| Package repos | APT repositories | YUM/DNF repositories |
| Config location | `/etc/apt/` | `/etc/yum.repos.d/` |
| Cache location | `/var/cache/apt/` | `/var/cache/yum/` |

```bash
# apt (Ubuntu/Debian)
apt update                    # Refresh package list
apt upgrade                   # Upgrade all installed packages
apt install nginx             # Install package
apt remove nginx              # Remove package (keep config)
apt purge nginx               # Remove package + config files
apt search "web server"       # Search for packages
apt show nginx                # Show package details
apt list --installed          # List installed packages
apt autoremove                # Remove unused dependencies

# yum/dnf (RHEL/CentOS/Fedora)
yum update                    # Update all packages
yum install nginx             # Install package
yum remove nginx              # Remove package
yum search nginx              # Search packages
yum info nginx                # Package details
dnf install nginx             # dnf is modern replacement for yum
```

---

## Disk Partitioning & Mounting

```bash
# View disks and partitions
lsblk                      # Tree view of block devices
fdisk -l                   # List all partitions (detailed)
parted -l                  # Modern alternative to fdisk, supports GPT

# Partitioning (choose one tool)
fdisk /dev/sdb             # Interactive - MBR/legacy, simple menu (n, p, w)
parted /dev/sdb            # Interactive - supports GPT, large disks (>2TB)

# Create a filesystem on a partition
mkfs.ext4 /dev/sdb1        # Format as ext4
mkfs.xfs /dev/sdb1         # Format as XFS
mkswap /dev/sdb2           # Format as swap space

# Mount / unmount
mkdir /mnt/data
mount /dev/sdb1 /mnt/data       # Mount manually
umount /mnt/data                # Unmount
mount -a                        # Mount everything listed in /etc/fstab

# Enable swap
swapon /dev/sdb2
swapoff /dev/sdb2
swapon -s                       # Show active swap
```

### /etc/fstab Format

Defines what gets mounted automatically at boot (see [Mounting](#mounting-etcfstab--partitions)):
```text
<device>        <mount point>   <fs type>  <options>       <dump>  <pass>
/dev/sda1       /               ext4       defaults        0       1
/dev/sdb1       /mnt/data       ext4       defaults        0       2
UUID=xxxx-xxxx  none            swap       sw              0       0
```
- `dump`: 1 = back up with `dump` utility, 0 = skip
- `pass`: order `fsck` checks filesystems at boot; `0` = don't check, `1` = root first

---

## System Monitoring & Resources

### df — Disk Free

```bash
df -h       # Human-readable (KB, MB, GB)
df -H       # Same but uses 1000 instead of 1024
df -T       # Show filesystem type
df -i       # Show inode usage instead of space
df -hT      # Combine: human-readable + filesystem type
```

Example output:
```bash
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        50G   20G   30G  40% /
tmpfs           1.9G     0  1.9G   0% /dev/shm
/dev/sdb1       100G   80G   20G  80% /data
```

Reading the columns: Filesystem (device/partition) · Size (total) · Used · Avail · Use% · Mounted on.

> Pro tip: when `Use%` hits 90%+ on `/` (root), your system may start having issues — commonly checked in disk alert scripts.

### du — Disk Usage

```bash
du -sh /var/log          # Human-readable size of /var/log
du -sh *                 # Size of each item in current directory
du -h --max-depth=1 /    # Size of top-level dirs in root
du -h /home | sort -rh   # Sort dirs by size (largest first)
du -ah /etc              # All files and dirs with sizes
du -sh /var/log/*.log    # Size of individual log files

# Practical: Find top 10 largest directories
du -h /home | sort -rh | head -10

# Finding largest files, not just directories
find / -xdev -type f -exec du -h {} + | sort -rh | head -10
```

### System Resource Overview

```bash
# CPU and processes
top                      # Interactive process monitor
htop                     # Enhanced version of top
ps aux                   # Show all running processes
ps -ef                   # Full-format process list
vmstat 1                 # Virtual memory stats every 1 second
vmstat -s                # Summary memory stats
mpstat                   # Per-CPU statistics
pidstat                  # CPU usage per process
uptime                   # Load average overview.
# The three uptime numbers are averages of processes wanting CPU over the last 1/5/15 min.
# Compare against nproc — load 4.0 is fine on 8 cores, maxed out on 4.

# Memory
free -m                  # Memory in megabytes
free -h                  # Human-readable
cat /proc/meminfo        # Detailed memory information
sar -r                   # Memory usage statistics
slabtop                  # Kernel slab cache usage

# Disk usage
df -h                    # Filesystem disk usage
df -i                    # Inode usage
du -sh /path             # Size of a directory
du -ah                   # Size of all files and directories
du -sh *                 # Size of items in current directory
lsblk                    # Block devices and partitions
blkid                    # Filesystem UUIDs and types

# Disk I/O
iostat                   # I/O stats for disks
iostat -x 1              # Extended stats every 1 second
iotop                    # Real-time disk I/O per process

# CPU information
lscpu                    # CPU architecture details
cat /proc/cpuinfo        # Raw CPU information
nproc                    # Number of CPU cores
cat /proc/loadavg        # Current system load average

# Network I/O
iftop                    # Real-time network bandwidth by connection
nethogs                  # Network usage per process
sar -n DEV               # Network interface statistics

# System information
uname -a                 # Kernel and system information
hostnamectl              # Hostname and OS information
lsb_release -a           # Linux distribution details
cat /etc/os-release      # OS release information

# Running services
systemctl status                                    # List failed and loaded services
systemctl --type=service                            # List all services
systemctl list-units --type=service --state=running

# System logs
journalctl                # View systemd logs
journalctl -xe            # Recent errors
dmesg                     # Kernel messages

# Open files
lsof                      # List all open files
lsof -p PID                # Files opened by a process

# Hardware information
lsmem                     # Memory layout
lspci                     # PCI devices
lsusb                     # USB devices
dmidecode                 # BIOS and hardware information (root)

# Monitor commands continuously
watch free -h             # Refresh memory usage
watch df -h                # Refresh disk usage
watch uptime                # Refresh system load
watch ps aux                 # Refresh process list

# Shutdown/reboot commands
shutdown -h now         # Shutdown immediately
shutdown -r now         # Reboot immediately
reboot                  # Reboot
poweroff                # Power off
shutdown -r +5 "Rebooting in 5 mins"   # Scheduled with message
shutdown -c             # Cancel a scheduled shutdown
```

### ulimit — Per-Process Resource Limits

`ulimit` controls the resource limits (file handles, memory, processes, etc.) available to processes started from the current shell — commonly checked/tuned for servers running databases or high-connection services.

```bash
ulimit -a               # show all current limits
ulimit -n                # max open file descriptors
ulimit -n 4096            # set max open file descriptors (session only)
ulimit -u                  # max number of user processes
ulimit -Hn                  # show the hard limit (ceiling) for open files
ulimit -Sn                   # show the soft limit (current enforced value)
```
> Permanent changes go in `/etc/security/limits.conf`, not in a shell session (session changes reset on logout).

---

## Process Management

### ps vs top

| Feature | `ps` | `top` |
|---------|------|-------|
| View type | Static snapshot | Dynamic real-time |
| Auto-refresh | No | Yes (every 3 seconds) |
| Interactive | No | Yes (press keys to interact) |
| Use case | Quick one-time check | Ongoing monitoring |

```bash
# ps - Process Snapshot
ps              # Processes in current shell
ps -e           # All processes on system
ps -ef          # Full format: UID, PID, PPID, CPU, start time
ps -ef | grep nginx    # Find specific process
ps aux          # BSD format: user, CPU%, MEM%, command
ps aux --sort=-%cpu    # Sort by CPU usage (descending)
ps aux --sort=-%mem    # Sort by memory usage
```

Example output of `ps -ef`:
```text
UID        PID  PPID  C STIME TTY          TIME CMD
root         1     0  0 09:01 ?        00:00:03 /sbin/init
hitesh    1234  1200  0 09:05 pts/0    00:00:00 bash
```

**Process STAT codes:**

| Code | Meaning | Details |
|------|---------|---------|
| `R` | Running/runnable | The process is currently running on a CPU or is ready and waiting to be scheduled. |
| `S` | Sleeping | The process is waiting for an event or resource, such as input, a timer, or another process. This is normal for many processes when they are idle. |
| `D` | Uninterruptible sleep | The process is usually waiting for I/O, such as disk or device operations. It generally cannot be interrupted until the operation completes. |
| `Z` | Zombie | The process has **finished execution**, but its parent process has not yet collected its exit status. The process is already dead, but a small entry remains in the process table until it is **reaped** by its parent. |
| `T` | Stopped | The process has been suspended, usually by a signal such as `SIGSTOP` or `SIGTSTP`. It is not currently executing until it is continued. |


> You can't kill a zombie directly — it's already dead. Fix it by killing/fixing its
> **parent** so the parent reaps it. If the parent dies first, the zombie is
> re-parented to `init`/`systemd` (PID 1), which reaps it automatically.

```bash
# top - Interactive Process Monitor
top             # Launch top
# While inside top:
# q = quit
# k = kill a process (enter PID)
# M = sort by memory
# P = sort by CPU
# u = filter by user
# 1 = show per-CPU stats
```
> Alternative: `htop` is a more user-friendly, colored version of `top`. Install with: `apt install htop`

### nice / renice — Process Priority

Every process has a **niceness** value from `-20` (highest priority) to `19` (lowest priority). Default is `0`. Lower niceness = more CPU priority.

```bash
nice -n 10 ./script.sh        # start a process with lower priority (nice to others)
nice -n -5 ./script.sh        # higher priority (requires root for negative values)
renice 5 -p PID                # change priority of an already-running process
renice -n -10 -p PID           # requires sudo for negative values
ps -o pid,ni,cmd -p PID        # check a process's current niceness
```
> Rule of thumb: raise niceness (be "nicer") for background/batch jobs so they don't starve interactive processes.

### Kill, Background & Foreground

```bash
# List processes
ps -ef | grep nginx            # Find process
ps aux --sort=-%cpu | head     # Top CPU consumers

# Kill processes
kill PID                       # Send SIGTERM (graceful)
kill -9 PID                    # Send SIGKILL (force)
kill -15 PID                   # Send SIGTERM explicitly
kill -l                        # list all available signal names and numbers
kill -l 9                      # look up the name for signal number 9 (SIGKILL)
killall nginx                  # Kill all processes named nginx
pkill -u hitesh                # Kill all processes by user

# Background/foreground
command &                      # Run in background
jobs                           # List background jobs
fg %1                          # Bring job 1 to foreground
bg %1                          # Send to background
nohup command &                # Persist after logout

# Suspend and resume
Ctrl+Z              # suspend current foreground job
bg                  # resume suspended job in background
fg                  # bring background job to foreground
disown %1           # remove job from shell's job table (keeps running after logout)

command1 & command2 &
wait                   # pause script until ALL background jobs finish
wait $!                # wait for a specific PID (last backgrounded process)
```

*kill vs pkill vs killall:*
```bash
kill PID              # kill by process ID
pkill nginx            # kill by process name (pattern match)
killall nginx          # kill all processes with exact name match
```

### Quick Interview One-Liners

- **`kill` vs `kill -9`?** `kill` (SIGTERM) asks the process to shut down gracefully — it can catch the signal and clean up first. `kill -9` (SIGKILL) terminates it immediately at the kernel level — it cannot be caught, ignored, or blocked, so no cleanup happens.
- **Process vs Program?** A program is a static file on disk (executable code, not running). A process is a program in execution — loaded into memory, with its own PID, memory space, and system resources.
- **What happens to a hard link's data if the original file is deleted?** Nothing — the data survives. Hard links point to the same inode, and the data is only actually removed once the *link count* on that inode drops to zero (i.e., every hard link pointing to it has been deleted).

---

## Scheduling (cron & at)

| Feature | `cron` | `at` |
|---------|--------|------|
| Purpose | Recurring/scheduled tasks | One-time future tasks |
| Config file | `/etc/crontab`, `/var/spool/cron/` | No config file |
| Frequency | Runs repeatedly on schedule | Runs once at specified time |
| Persistence | Survives reboots | Runs once and is done |
| Use case | Backups, cleanups, monitoring | One-off maintenance task |

### Cron Syntax

```text
* * * * * command_to_execute
| | | | |
| | | | +-- Day of week (0=Sun, 6=Sat)
| | | +---- Month (1-12)
| | +------ Day of month (1-31)
| +-------- Hour (0-23)
+---------- Minute (0-59)
```

```bash
crontab -e    # Edit current user's cron jobs
crontab -l    # List current user's cron jobs
crontab -r    # Remove all cron jobs

# Common cron schedules:
0 1 * * *      /home/user/backup.sh     # Daily at 1:00 AM
*/5 * * * *    /usr/bin/monitor.sh      # Every 5 minutes
0 0 * * 0      /scripts/weekly.sh       # Every Sunday midnight
0 9-17 * * 1-5 /scripts/workday.sh      # 9AM-5PM Mon-Fri (hourly)
@reboot        /scripts/startup.sh      # Run at boot
@daily         /scripts/daily.sh        # Alias for 0 0 * * *
```

### at Command

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

## Logs

Linux stores logs in `/var/log/`. Different services write to different files.

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

### journalctl — View systemd Journal Logs

`journalctl` displays logs collected by the systemd journal. It is commonly used to troubleshoot services, boot problems, authentication issues, and system errors.

```bash
journalctl
```

Show recent log entries:

```bash
journalctl -n 50
```

Show logs for a particular service:

```bash
journalctl -u nginx
```

Follow logs in real time:

```bash
journalctl -f
```

Show logs from the current boot:

```bash
journalctl -b
```

Show logs from the previous boot:

```bash
journalctl -b -1
```

Show logs since a specific time:

```bash
journalctl --since "1 hour ago"
```

```bash
journalctl --since "2026-09-21 10:00:00"
```

Show only warning/error-level messages:

```bash
journalctl -p warning
journalctl -p err
```

Combine service filtering and live monitoring:

```bash
journalctl -u nginx -f
```

Show kernel-related journal messages:

```bash
journalctl -k
```

Useful troubleshooting pattern:

```bash
systemctl status nginx
journalctl -u nginx -n 100
journalctl -u nginx -f
```

> `journalctl` works with systems using systemd's journal. Traditional text logs such as `/var/log/syslog` may still exist depending on the distribution and logging configuration.

---

## Links (Soft vs Hard)

### What Is an Inode?
Every file on Linux is represented by an **inode** — a data structure storing metadata (permissions, owner, size, timestamps, pointers to data blocks) but **not** the filename itself. The filename is just a label in a directory that points to an inode number.

```bash
ls -i file.txt        # show a file's inode number
df -i                  # show inode usage per filesystem
```
This is why you can run out of disk space ("No space left on device") even with free bytes available — if inodes are exhausted, no new files can be created.

| Feature | Soft Link (Symbolic) | Hard Link |
|---------|---------------------|-----------|
| Points to | File name/path | File inode (actual data) |
| Breaks if original deleted | Yes (dangling link) | No (data persists) |
| Can link directories | Yes | No |
| Cross filesystem links | Yes | No |
| Shows as separate file type | `l` in `ls -l` | Appears identical |
| File size shown | Size of path string | Size of actual file |

```bash
# Soft Link (Symbolic Link)
ln -s /path/to/original link_name

# Hard Link
ln /path/to/original link_name
```

Examples:
```bash
ln -s /var/www/html /home/hitesh/www
# Creates a shortcut named 'www' pointing to /var/www/html.
# Opening /home/hitesh/www actually accesses /var/www/html.

ln -s /usr/bin/python3 /usr/bin/python
# Creates another name (alias) for the python3 executable.

ln important.txt backup_link.txt
# Creates a hard link.
# Both filenames point to the same file (same inode).
# Editing either file changes the same data.
```

Viewing links:
```bash
ls -l
# Soft links are displayed with -> showing the target path.
# Example:
# mysyslog -> /var/log/syslog

ls -li
# Displays inode numbers.
# Hard-linked files have exactly the same inode number,
# proving they are the same file with different names.

readlink -f link_name
# Prints the final absolute path that a soft link points to.
```

Soft link example:
```bash
$ ln -s /var/log/syslog mysyslog
# Creates a symbolic link named "mysyslog".

$ ls -l mysyslog
lrwxrwxrwx 1 hitesh hitesh 15 Jun 10 10:00 mysyslog -> /var/log/syslog
```

**Gotcha — moving a symlink vs moving its target:**
```bash
ln -s /tmp/data.txt link.txt

mv link.txt /home/user/     # fine — the link itself just moves, still points to /tmp/data.txt

mv /tmp/data.txt /tmp/new.txt   # BREAKS the link — link.txt now points to a path that no longer exists ("dangling link")
```
A symlink stores a **path string**, not a reference to the file itself — moving or renaming the *target* breaks every symlink pointing to the old path. Hard links are immune to this because they point to the inode, not a path.

**Interview Q&A:**
- *Can you hard-link a directory?* No — hard links to directories are disallowed by the filesystem (to prevent loops in the directory tree). Only symbolic links can point to directories.
- *Can a hard link cross filesystems/partitions?* No — hard links require the same inode table, so source and link must be on the same filesystem. Symlinks have no such restriction.
- *If you `cat` a broken symlink, what happens?* `cat: link.txt: No such file or directory` — the link itself still exists (`ls -l` shows it), but it points nowhere.

---

## SELinux

Security-Enhanced Linux (SELinux) is a mandatory access control (MAC) security framework built into the Linux kernel — primarily used in RHEL/CentOS systems.

Traditional Linux uses Discretionary Access Control (DAC) — owner decides permissions. SELinux adds Mandatory Access Control (MAC) — system policy controls access regardless of owner.

| Mode | Behavior |
|------|----------|
| `enforcing` | Actively blocks and logs policy violations |
| `permissive` | Only logs violations (does NOT block) — used for debugging |
| `disabled` | SELinux completely off |

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

## Encoding & Misc Utilities

### Base64

An encoding algorithm, **not** encryption. Encoding converts data into text-safe format; decoding reverses it.

```bash
# Syntax
base64 [OPTION]... [FILE]

# Encode a file
echo "Hello World" > file.txt
base64 file.txt

# Decode a File
cat encoded.txt
base64 -d encoded.txt

# Encode Text
echo "Linux" | base64        # TGludXgK
echo -n "Linux" | base64     # No trailing newline: TGludXg=

# Decode Text
echo "TGludXg=" | base64 -d

# Encode and Decode Binary Files
base64 image.png > image.b64
base64 -d image.b64 > image_copy.png

# Encode and Decode JSON
echo -n '{"name":"Alice"}' | base64
echo "eyJuYW1lIjoiQWxpY2UifQ==" | base64 -d
```

---

## Hashing

```bash
# Hashing File
echo "Hello" > test.txt
md5sum test.txt

echo "hello" | md5sum    # Hashing text
```
---

## Shell Scripting Basics

### What Is a Shell Script?

A shell script is a plain text file containing a series of Linux/Unix commands executed sequentially by the shell interpreter (`bash`, `sh`, `zsh`, etc.). Used for automating repetitive tasks (backups, deployments, cleanups), batch processing, system administration, and DevOps/CI-CD pipelines.

### Basic Script Structure

```bash
#!/bin/bash
# This is a comment
# Script: hello.sh
# Purpose: Basic shell script example
# Author: Hitesh
# Date: 2024-06-10

# Variables
NAME="Hitesh"
echo "Hello, $NAME"     # Hello, Hitesh   (double quotes expand variables)
echo 'Hello, $NAME'     # Hello, $NAME    (single quotes DO NOT expand — printed literally)
DATE=$(date +%Y-%m-%d)

# Main logic
echo "Hello, $NAME!"
echo "Today is: $DATE"
echo "Script completed successfully."

# Commenting Out Multiple Lines - Bash has no native block-comment syntax, but this trick works:
: <<'COMMENT'
This whole block
is ignored by the shell
COMMENT
# For short blocks, prefixing each line with `#` is simpler and clearer.
```

### Running a Script
./script.sh instead of just script.sh - Even after chmod +x, running just script.sh fails with "command not found" — the current directory (.) is intentionally not in $PATH by default (security reasons: prevents accidentally running a malicious script named like a real command). That's why you must specify the path explicitly with ./script.sh.
```bash
# Method 1: Make executable and run
chmod +x hello.sh
./hello.sh

# Method 2: Run with bash directly
bash hello.sh

# Method 3: Source (run in current shell)
source hello.sh
. hello.sh    # Shorthand for source

# Full workflow
cat > myscript.sh << 'EOF'
#!/bin/bash
echo "Hello World"
EOF

chmod +x myscript.sh
./myscript.sh           # Run from current directory
bash myscript.sh        # Explicitly use bash
sh myscript.sh          # Use sh interpreter
/full/path/myscript.sh  # Use full path

sudo ./myscript.sh       # Run as root
sudo bash myscript.sh

./myscript.sh &          # Run in background
nohup ./myscript.sh &    # Keep running after logout

./myscript.sh arg1 arg2  # Pass arguments
```

### The Shebang (`#!`)

The first line of a script — tells the OS which interpreter to use.

```bash
#!/bin/bash         # Use bash shell
#!/bin/sh           # Use POSIX sh (more portable)
#!/usr/bin/python3  # Run as Python 3 script
#!/usr/bin/env node # Run as Node.js script (portable path)
#!/usr/bin/perl     # Run as Perl script
```

```bash
#!/usr/bin/env bash    # More portable - finds bash in PATH
#!/bin/bash            # Hardcoded path - may fail if bash is elsewhere
```
> Best practice: use `#!/usr/bin/env bash` for portability across systems.

```bash
# Check what shell is being used
echo $SHELL       # Your login shell
echo $0           # Current shell or script name
```

### Variables

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

# declare — Variable Attributes
declare -i count=5        # integer type - arithmetic works without $(( ))
count=count+1
echo $count                # 6

declare -r PI=3.14         # read-only, same effect as `readonly`
declare -x APP_ENV=prod    # exported, same effect as `export`
declare -a arr             # explicitly declare an indexed array
declare -A map             # explicitly declare an associative array
declare -p count            # print a variable's declared attributes and value

# Unset a variable
unset age
echo "Age: $age"    # Will print nothing

# Default values
echo ${undefined_var:-"default value"}   # Use default if unset
echo ${name:="Anonymous"}                # Assign default if unset
```

> Variable rules: no spaces around `=`; names are case-sensitive (`NAME` != `name`); convention: UPPERCASE for constants, lowercase for regular vars.

### Special Variables

```bash
# Environment variables
$HOME        # Current user's home directory
$PATH        # Directories searched for commands
$USER        # Current username
$HOSTNAME    # Machine hostname
$SHELL       # Current shell
$PWD         # Current working directory
$OLDPWD      # Previous working directory
$LANG        # Current system language/locale

# Shell variables
$RANDOM      # Random number
$LINENO      # Current line number in script

# Process variables
$$           # PID of current shell/script
$!           # PID of last background process
$?           # Exit status of last command (0 = success, non-zero = failure)
```

**`"$@"` vs `"$*"` — the difference that actually matters:**
```bash
set -- "a b" "c"
for x in "$@"; do echo "[$x]"; done   # [a b]  [c]   -> preserves each argument
for x in "$*"; do echo "[$x]"; done   # [a b c]        -> merges into ONE string
```
> Interview one-liner: `"$@"` expands to separate quoted words (safe for loops over arguments), `"$*"` expands to a single word joined by the first character of `$IFS`. Always prefer `"$@"` when looping over script arguments.

```bash
# Script positional parameters
$0           # Script name
$1           # First argument
$2           # Second argument
$#           # Number of arguments
$@           # All arguments (preserves each argument)
$*           # All arguments (as a single string)
```

```bash
# $PATH is a colon-separated list of directories the shell searches for commands.
echo $PATH    # /usr/local/bin:/usr/bin:/bin

# Add a new directory to PATH (append):
export PATH=$PATH:/home/hitesh/scripts
# Now scripts in that folder can run without ./ or full path
```
**Interview Q&A:** *What happens if two commands with the same name exist in different `$PATH` directories?*
The shell searches `$PATH` directories **in order, left to right**, and runs the **first match** it finds. `which command` or `type command` tells you exactly which one will execute. This is also why prepending vs appending to `$PATH` matters:
```bash
export PATH="/custom/bin:$PATH"   # custom/bin checked FIRST (takes priority)
export PATH="$PATH:/custom/bin"   # custom/bin checked LAST (fallback only)
```

### Shell Variable vs Environment Variable

| Type | Scope | Set With | Visible To |
|------|-------|----------|-----------|
| Shell variable | Current shell only | `var=value` | Only the shell it was defined in |
| Environment variable | Current shell + all child processes | `export var=value` | The shell AND any program/script it launches |

> Interview one-liner: *Every environment variable is a shell variable, but not every shell variable is an environment variable — `export` is what promotes one to the other.*

### export and Environment Variables

By default, a variable is only available in the current shell. `export` makes it available to any child processes/subshells.

```bash
# Shell variable (local to this shell only)
name="Hitesh"
bash -c 'echo $name'    # prints nothing - child shell can't see it

# Environment variable (passed to child processes)
export name="Hitesh"
bash -c 'echo $name'    # prints "Hitesh"

# View all environment variables
env
printenv

# Export inline for a single command
MY_VAR=test command
```

### Positional Parameters

```bash
./script.sh arg1 arg2 arg3
```

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

### getopts

Parses flag-style options (`-v`, `-f file`) instead of relying only on positional order.

```bash
#!/bin/bash
while getopts "v:f:h" opt; do
    case $opt in
        v) VERSION="$OPTARG" ;;
        f) FILE="$OPTARG" ;;
        h) echo "Usage: $0 -v version -f file"; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG"; exit 1 ;;
    esac
done
# Run: ./script.sh -v 1.2.3 -f config.txt
```

### Conditionals — `[ ]` vs `[[ ]]`

```text
[ ] -> POSIX test command, works in all shells (sh, dash, bash)
       no pattern matching, word-splitting can cause bugs with unquoted variables

[[ ]] -> bash-only extended test, safer, supports =~ (regex) and && / || directly
```

```bash
# [ ] needs quotes to be safe:
if [ "$name" == "hitesh" ]; then echo "match"; fi

# [[ ]] handles unquoted vars safely and supports regex:
if [[ $name == "hitesh" ]]; then echo "match"; fi
if [[ $email =~ ^[a-z]+@[a-z]+\.com$ ]]; then echo "valid email"; fi

# (( )) -> arithmetic evaluation context, no need for -eq/-gt, no $ needed on vars
if (( x > 5 )); then echo "x is greater than 5"; fi
if (( count % 2 == 0 )); then echo "even"; fi
```

### if / elif / else Syntax

```bash
if [ condition ]; then
    # code if true
elif [ condition ]; then
    # code if elif is true
else
    # code if all above false
fi
```

**Numeric comparison operators:** `-eq` equal, `-ne` not equal, `-gt` greater than, `-lt` less than, `-ge` greater or equal, `-le` less or equal

**String comparison operators:** `==`/`=` equal, `!=` not equal, `-z` empty, `-n` not empty

**File test operators:** `-f` regular file exists, `-d` directory exists, `-e` exists, `-r` readable, `-w` writable, `-x` executable, `-s` exists and not empty

### The test Command

```bash
# [ $a -eq $b ] is shorthand for the test command:
test $a -eq $b
echo $?          # 0 = true, 1 = false

# These are equivalent:
if [ -f file.txt ]; then echo "exists"; fi
if test -f file.txt; then echo "exists"; fi
```

### Conditional Examples

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

# Using [[ ]] (bash extended test - more features)
if [[ $name =~ ^[A-Z] ]]; then
    echo "Name starts with uppercase"
fi
```

### Loops

```bash
#!/bin/bash

# for loop - Loop over a list
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

```bash
#!/bin/bash

# while loop - repeat while condition is true
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

# until loop (opposite of while - runs until condition is TRUE)
until [ -f /tmp/done.flag ]; do
    echo "Waiting for task to complete..."
    sleep 2
done
echo "Task completed!"
```

```bash
# select — Interactive Menus
select fruit in "apple" "banana" "exit"; do
    case $fruit in
        apple) echo "You chose apple" ;;
        banana) echo "You chose banana" ;;
        exit) break ;;
    esac
done
```

### continue and break

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

### Reading User Input

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
    echo "-> $line"
done < config.txt

# Read with delimiter
IFS=',' read -ra items <<< "apple,banana,mango"
for item in "${items[@]}"; do
    echo "Item: $item"
done
```

### printf vs echo

```bash
echo "Hello"                    # simple output, adds newline
printf "Hello\n"                # more control, no automatic newline
printf "%s is %d\n" "age" 25    # formatted output like C's printf
printf "%-10s|%5d\n" "name" 42  # column alignment
echo -n "No newline"        # suppress trailing newline
echo -e "Line1\nLine2"      # enable interpretation of \n, \t escape sequences
echo "Line1\nLine2"         # without -e, \n prints literally (not a real newline)
```

### `$?` — Exit Status

`$?` is the exit status of the last executed command — `0` = success, any non-zero value (1–255) = failure.

```bash
#!/bin/bash

# Check if previous command succeeded
ping -c 1 google.com > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Internet is reachable"
else
    echo "No internet connection!"
fi
```

Common exit codes: `0` Success · `1` General error · `2` Misuse of shell command · `126` Command found but not executable · `127` Command not found · `130` Script terminated with Ctrl+C

```bash
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

```bash
# exit with custom codes
#!/bin/bash
if [ ! -f "$1" ]; then
    echo "Error: file not found"
    exit 2
fi
echo "File found"
exit 0
```

### nano basics
Shortcut	Action
Ctrl+O	Save (Write Out) — press Enter to confirm filename
Ctrl+X	Exit
Ctrl+K	Cut current line
Ctrl+U	Paste
Ctrl+W	Search
Ctrl+G	Help menu

### Basic vi/vim Commands
> New to the terminal? Start with `nano` — it's simpler and shows shortcuts on-screen. Learn `vi`/`vim` once you're comfortable, since it's the editor guaranteed to exist on every server.

```bash
vi filename        # open file (or create if it doesn't exist)
```

Modes: **Normal** (default — navigate, delete, copy) · **Insert** (type text, press `i`) · **Command** (save/quit, press `:`)

```text
i          # enter insert mode
Esc        # back to normal mode
:w         # save
:q         # quit
:wq        # save and quit
:q!        # quit without saving
dd         # delete current line
yy         # copy (yank) current line
p          # paste
/text      # search for "text"
```

### Debugging a Script

```bash
# Method 0: Check syntax only, without running anything
bash -n script.sh
# Reports syntax errors (missing "fi", unmatched quotes, etc.)
# without executing a single command — always run this first

# Method 1: Run with -x flag (trace mode - prints each command before executing)
bash -x script.sh

# Method 2: Run with -v flag (verbose - prints script lines as they're read)
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

## Advanced Shell Scripting

### Subshell `( )` vs Grouping `{ }`
```bash
(cd /tmp && rm -rf *)     # runs in a SUBSHELL — cd doesn't affect the parent shell
{ cd /tmp && rm -rf *; }  # runs in the CURRENT shell — cd affects your session; needs trailing ;

x=10
(x=20); echo $x    # prints 10 — subshell variables don't leak out
{ x=20; }; echo $x  # prints 20 — same shell, variable changes persist
```
> Interview one-liner: `()` forks a child shell (isolates variables/cd), `{}` does not.

### Functions

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
# `return` only exits the function (control goes back to the caller with an exit status in `$?`). `exit` terminates the entire script/shell. Using `exit` inside a function you meant to just `return` from is a common bug — it kills the whole script.

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
echo "Local: $local_var"      # Empty - local variable not accessible outside

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

### case Statement

Clean alternative to multiple if-elif conditions — especially useful for menus and option parsing.

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

### Arrays

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
    echo "-> $fruit"
done

# Array with index
for i in "${!fruits[@]}"; do
    echo "[$i] = ${fruits[$i]}"
done

# Remove element
unset fruits[1]         # Remove "banana"

# Associative arrays (key-value pairs - like dictionaries)
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
    ping -c 1 $server > /dev/null && echo "OK $server UP" || echo "FAIL $server DOWN"
done
```

### String Manipulation

```bash
str="Hello World"

echo ${#str}              # length: 11
echo ${str:0:5}           # substring from index 0, length 5: "Hello"
echo ${str:6}              # from index 6 to end: "World"
echo ${str/World/Bash}    # replace first match: "Hello Bash"
echo ${str//o/0}          # replace all matches: "Hell0 W0rld"
echo ${str^^}              # uppercase: "HELLO WORLD"
echo ${str,,}              # lowercase: "hello world"
```

### Arithmetic Expansion `$(( ))`
The modern, preferred way to do math in bash — evaluates an expression and returns the result.
```bash
echo $((5 + 3))          # 8
x=$((10 * 2))
echo $x                  # 20
echo $((i % 2))           # remainder (used constantly for even/odd checks)
count=$((count + 1))      # increment a variable
```
Supports `+ - * / %` and parentheses for grouping. Prefer this over `let` or `expr` — no risk of word-splitting, and it's easier to read.
> **Gotcha:** `$(( ))` only supports integers. `echo $((5/2))` gives `2`, not `2.5`.
> For decimals, use `bc` or `awk`:
```bash
echo "5/2" | bc -l        # 2.50000000000000000000
awk 'BEGIN{print 5/2}'    # 2.5
```

### Arithmetic — let and expr

```bash
let x=5+3
echo $x            # 8

y=$(expr 5 + 3)
echo $y            # 8
```

### trap — Signal Handling

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
```

Common signals: `SIGINT (2)` Ctrl+C · `SIGTERM (15)` kill command (graceful) · `SIGKILL (9)` kill -9 (cannot be caught!) · `SIGHUP (1)` Terminal closed / reload config · `EXIT` Script exits (any reason) · `ERR` Any command fails

```bash
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

### exec

Replaces the current shell process with a new command instead of spawning a child.

```bash
exec bash              # replaces current shell with a new bash instance
exec > output.log      # redirect all subsequent script output to a file
exec 2>&1              # redirect stderr to stdout for rest of script
```

### `==` vs `-eq`

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
    echo "This is string comparison - '10' is not '9' as strings"
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

### Checking File/Directory Existence

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

### set -e — Exit on Error

`set -e` makes the script exit immediately when any command returns a non-zero exit status (fails).

```bash
#!/bin/bash
set -e    # Exit on error

echo "Step 1: Starting"
cp /etc/hosts /tmp/hosts_backup    # If this fails, script stops
echo "Step 2: File copied"
ls /nonexistent/dir                # This fails - script exits here
echo "Step 3: Never reached"      # This will NOT execute
```

Recommended script safety settings:
```bash
#!/bin/bash
set -euo pipefail

# -e  = Exit on error
# -u  = Treat unset variables as errors
# -o pipefail = Exit if any part of a pipe fails
```

Bypassing `set -e` when needed:
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

## I/O Redirection & Pipelines

Linux programs use three standard streams:
- **stdin (0)** — Standard Input (where a program reads input from, usually the keyboard)
- **stdout (1)** — Standard Output (normal output shown on the terminal)
- **stderr (2)** — Standard Error (error messages shown on the terminal)

| Symbol | Purpose |
|--------|---------|
| `>` | Redirect stdout to a file (overwrites existing contents) |
| `>>` | Redirect stdout to a file, appending instead of replacing |
| `2>` | Redirect stderr only to a file; normal output still shows on terminal |
| `2>>` | Append stderr to a file without overwriting existing contents |
| `&>` | Redirect both stdout and stderr to the same file (Bash shortcut) |
| `2>&1` | Redirect stderr to wherever stdout is currently going |
| `< file` | Use the specified file as the program's stdin instead of the keyboard |
| `/dev/null` | A "black hole" device — anything redirected here is discarded permanently |

> Easy to remember: `>` replace · `>>` append · `2>` errors only · `2>&1` combine normal output + errors · `<` read input from a file · `/dev/null` throw the output away.

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

### tee — Read stdin and Write to Both Screen and File

`tee` reads data from standard input and writes it both to standard output and to one or more files.

This makes it useful when you want to **see command output on the terminal while also saving it to a file**.

```bash
ls -l | tee output.txt
```

The output is displayed on the terminal and saved to `output.txt`.

Append instead of overwriting:

```bash
ls -l | tee -a output.txt
```

`-a` appends to the file.

#### Common Examples

Save command output while still seeing it:

```bash
df -h | tee disk_usage.txt
```

Save a pipeline result:

```bash
ps aux | grep nginx | tee nginx_processes.txt
```

Use `tee` with `sudo` when writing to a protected file:

```bash
echo "test" | sudo tee /etc/example.conf
```

Append to a protected file:

```bash
echo "another line" | sudo tee -a /etc/example.conf
```

> `sudo echo "text" > /etc/example.conf` usually does **not** work as expected because the shell performs the `>` redirection before `sudo` is applied. `sudo tee` allows the file-writing operation itself to run with elevated privileges.

Conceptually:

```text
command
   ↓
stdout
   ↓
 tee ─────→ file
   │
   └──────→ terminal
```

### Pipelines

A pipeline (`|`) connects the stdout of one command to the stdin of another, chaining commands to process data progressively.

```bash
# Basic pipeline
ls -l | grep ".sh"                    # Find .sh files
cat /etc/passwd | grep "hitesh"      # Find user
ps -ef | grep nginx                   # Find process

# Multiple pipes (pipeline chain)
cat /var/log/auth.log | grep "Failed" | awk '{print $11}' | sort | uniq -c | sort -rn | head -10
# Find top 10 IPs with failed SSH attempts

# Real-world pipeline examples
cat file.txt | wc -l                          # Count lines in a file
wc -l < file.txt                              # More efficient (no cat needed)

ps aux | grep nginx | grep -v grep | wc -l    # Find and count processes

ps aux --sort=-%cpu | head -5                 # Monitor CPU-heavy processes

cat access.log | awk '{print $1}' | sort | uniq   # Find unique IPs in a web log

echo "Hello World 2024" | sed 's/World/Linux/' | awk '{print $1, $3}'   # sed + awk

# Named pipe (FIFO)
mkfifo mypipe
command1 > mypipe &
command2 < mypipe
```

### Here-Documents (heredoc)

Allows providing multi-line input to a command inline in the script.

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

### Process Substitution
Lets a command's output be treated as if it were a file.
```bash
diff <(sort file1.txt) <(sort file2.txt)   # compare two sorted streams without temp files
cat <(echo "a") <(echo "b")
```

---

## Linux Directory Structure

The Linux filesystem follows the Filesystem Hierarchy Standard (FHS), which standardizes directory structure across all distributions.

```text
/        # Root directory; the top-level directory. Everything in Linux starts from here.
/bin     # Essential user commands (ls, cp, mv, rm, cat, etc.). Required for booting and basic system operation.
/boot    # Bootloader files, Linux kernel (vmlinuz), initramfs, and GRUB configuration used during system startup.
/dev     # Device files representing hardware (disks, USB, terminals, etc.). In Linux, devices are treated as files.
/etc     # System-wide configuration files (network, users, services, SSH, DNS, etc.). No user data is stored here.
/home    # Home directories for normal users (e.g., /home/alice, /home/john). Stores personal files and settings.
/lib     # Essential shared libraries required by programs in /bin and /sbin. Similar to DLLs in Windows.
/media   # Automatically mounted removable media like USB drives, DVDs, and external hard disks.
/mnt     # Temporary mount point used by administrators for manually mounting filesystems.
/opt     # Optional or third-party software installed outside the default package manager (e.g., Oracle, Tomcat).
/proc    # Virtual filesystem containing live process and kernel information (CPU, memory, processes). Files are generated by the kernel, not stored on disk.
/root    # Home directory of the root (administrator) user. Different from the root directory (/).
/run     # Runtime data such as PID files, sockets, and lock files. Cleared automatically after reboot.
/sbin    # Essential system administration commands (fsck, reboot, shutdown, mkfs, iptables). Mainly used by root.
/srv     # Data served by system services such as web servers (HTTP), FTP servers, or Git repositories.
/sys     # Virtual filesystem exposing kernel, driver, and hardware information. Used for hardware management.
/tmp     # Temporary files created by users and applications. Often cleaned automatically after reboot or periodically.
/usr     # User applications, utilities, libraries, documentation, and shared resources. Most installed software resides here.
/var     # Variable data that changes frequently, including logs, cache, mail, spool files, databases, and temporary application data.
```

`/etc/hostname` stores just this machine's hostname (one line). `/etc/hosts` maps hostnames/IPs for local name resolution:

```bash
cat /etc/hostname
# webserver01

cat /etc/hosts
# 127.0.0.1   localhost
# 192.168.1.5 webserver01
```

### Quick Reference Table

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

## Linux Boot Process

### Complete Boot Flow

```text
Power ON
BIOS / UEFI -> POST (Power-On Self Test) -> Detects hardware
Bootloader (GRUB) -> Loads kernel + initramfs into memory
Linux Kernel -> Initializes drivers, mounts root filesystem
systemd (PID 1) -> Starts services and targets
Login Prompt (CLI or GUI)
```

### Stage 1 — BIOS / UEFI

- Performs POST (Power-On Self Test)
- Detects and initializes hardware (CPU, RAM, disk, keyboard)
- Finds bootable device from configured boot order
- Loads bootloader from MBR (legacy) or EFI partition (modern UEFI)

| BIOS | UEFI |
|------|------|
| Legacy standard | Modern replacement |
| Uses MBR (512 bytes) | Uses GPT partition table |
| Limited to 2TB drives | Supports drives >2TB |
| Slower boot | Faster boot |
| Basic text interface | Graphical interface possible |

### Stage 2 — GRUB Bootloader

- Located at `/boot/grub/`
- Presents boot menu (OS selection, kernel version selection)
- Loads the kernel (`/boot/vmlinuz-*`) and initramfs (`/boot/initrd.img-*`) into memory
- Passes kernel parameters (e.g., `quiet splash`)

```bash
# View/edit GRUB config
cat /etc/default/grub
sudo update-grub

# GRUB command line (if GRUB fails to boot, press 'e' to edit)
# grub rescue> - appears when GRUB is broken

# Fix broken GRUB:
grub-install /dev/sda
update-grub
```

### Stage 3 — Linux Kernel

- Decompresses itself into memory
- Initializes CPU, memory management, device drivers
- Mounts temporary root filesystem from initramfs
- Detects and loads hardware modules
- Mounts actual root filesystem (`/`)
- Starts the first user-space process: systemd (PID 1)

```bash
uname -r               # Show kernel version
dmesg                  # View kernel boot messages
dmesg | grep -i error  # Check for hardware errors during boot
ls /boot/               # View available kernels
```

### Stage 4 — systemd

- First userspace process (PID = 1)
- Manages all services, mounts, and targets
- Parallel service startup (faster than old init)

```bash
ps -p 1                          # Verify PID 1 is systemd
systemd-analyze                  # Show total boot time
systemd-analyze blame            # Time taken by each service
systemd-analyze critical-chain   # Critical path in boot

systemctl list-units --type=service    # All services
systemctl get-default                  # Current boot target
```

### Stage 5 — Targets (Replaced Runlevels)

| Old Runlevel | systemd Target | Purpose |
|-------------|----------------|---------|
| 0 | `poweroff.target` | Shutdown |
| 1 | `rescue.target` | Single-user mode |
| 2 | `multi-user.target` | Multi-user, no networking (Debian legacy) |
| 3 | `multi-user.target` | CLI only |
| 4 | unused | User-definable |
| 5 | `graphical.target` | GUI desktop |
| 6 | `reboot.target` | Reboot |

```bash
systemctl get-default                         # Current target
systemctl set-default multi-user.target       # Set CLI mode
systemctl set-default graphical.target        # Set GUI mode
systemctl isolate rescue.target               # Switch to rescue mode now
```

### Service Management with systemctl

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

## Practical Shell Script Examples

### 1. Directory Backup Script

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

### 2. Disk Usage Alert Script

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

### 3. Service Health Check

```bash
#!/bin/bash
SERVICES=("nginx" "mysql" "redis")

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "OK $service is running"
    else
        echo "DOWN $service is DOWN - attempting restart..."
        systemctl restart "$service" && echo "  -> Restarted successfully" || echo "  -> Restart FAILED!"
    fi
done
```

### 4. Bulk User Creation from File

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

### 5. Even or Odd Number Check

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

## Quick Reference Cheatsheet

### File Operations

```bash
ls -lah             # List all, long format, human-readable
cp -r src dst        # Copy recursively
mv old new           # Move/rename
rm -rf dir           # Force delete recursively
mkdir -p a/b/c        # Create nested dirs
touch file.txt        # Create empty file / update timestamp
```

### Text Processing

```bash
cat file             # Print file
less file             # Page through file
head -n 20 file        # First 20 lines
tail -f file            # Follow file in real time
grep -rn "text" .        # Recursive search with line numbers
sort file | uniq          # Sort + remove adjacent duplicates
cut -d: -f1 file           # Extract delimited field
awk '{print $1}' file       # Print first column
sed 's/old/new/g' file       # Replace text (global)
wc -l file                    # Count lines
```

### Process Management

```bash
ps aux             # All processes
top / htop         # Real-time monitor
kill -9 PID        # Force kill
jobs               # Background jobs
nohup cmd &        # Run persistently
```

### Permissions

```bash
chmod 755 file          # rwxr-xr-x
chmod +x file            # Add execute
chown user:group file     # Change owner
```

### Networking

```bash
ip addr show       # Show IPs
ss -tulnp          # Open ports
ping host          # Test connectivity
curl -I url        # HTTP headers
wget url            # Download
```

### Shell Scripting

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

## Scenario-based troubleshooting questions

Q. A developer created a testing program that is continuously writing to a log file /var/log/bad.log and filling up the disk. You can check for example with tail -f /var/log/bad.log.
This program is no longer needed. Find it and terminate it. Do not delete the log file.


```bash
sudo kill 1234
sudo lsof /var/log/bad.log
sudo fuser /var/log/bad.log
tail -f /var/log/bad.log

```

Q. Description: There's a web server access log file at /home/admin/access.log. The file consists of one line per HTTP request, with the requester's IP address at the beginning of each line (first column).
Findwhat's the IP address that has the most requests in this file (there's no tie; the IP is unique). Write the solution into a file /home/admin/highestip.txt. For example, if your solution is "1.2.3.4", you can do echo "1.2.3.4" > /home/admin/highestip.txt
```bash
awk '{print $1}' /home/admin/access.log | sort | uniq -c | sort -nr | head -1 | awk '{print $2}' > /home/admin/highestip.txt
```


*This document covers Linux Commands and Shell Scripting from beginner to DevOps-level. Practice these concepts hands-on for best results.*