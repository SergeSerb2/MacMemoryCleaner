# Security Policy

Mac Memory Cleaner asks for administrator rights once. This page explains what that
allows.

## Reporting a vulnerability

Please report security problems privately. Do not open a public issue.

Use GitHub's private vulnerability reporting: open the repository's **Security** tab, then
click **Report a vulnerability**. Include the app version, your macOS version, and the steps
to reproduce the problem. You can expect a first answer within a week.

Only the latest release gets security fixes.

## What the app can do as root

The app runs two commands as root: `purge` and `memory_pressure -S`. To run them without
asking for your password each time, the one-time setup installs this file:

```text
/etc/sudoers.d/macmemorycleaner-501     owner root:wheel, mode 0440, comment lines left out

#501 ALL = (root) NOPASSWD: /usr/sbin/purge "", /usr/bin/memory_pressure -S -l warn -s 2, /usr/bin/memory_pressure -S -l critical -s 2
```

`501` is your numeric user ID. Run the app binary with `--show-rule` to see your exact rule,
and with `--setup --dry-run` to see every command setup runs as root.

- The rule allows only those three exact command lines. sudo rejects any other arguments
  (`""` means "no arguments" for `purge`), any other command, and any other user.
- Each account gets its own file, so accounts on the same Mac never overwrite or remove
  each other's rule.
- The rule names your account by user ID, so no account name can turn into a sudoers
  keyword such as `ALL`.
- Setup writes the rule to a temporary file that sudo ignores, checks it with
  `visudo -c`, and only then moves it into place. A broken rule never goes live.
- **Trade-off:** any program that runs as your user can also run these three commands
  without a password. The worst it can do is slow your Mac down by purging caches over and
  over. It cannot read or change files, and it cannot run other commands as root.

To remove the rule, click **Remove…** in Settings › Cleaning, or run
`sudo rm /etc/sudoers.d/macmemorycleaner-$(id -u)`.

## Other facts

- The app makes no network connections and collects no data.
- To group helper processes under their app, the app calls the private libSystem function
  `responsibility_get_pid_responsible_for_pid`. This is the same lookup Activity Monitor
  uses. It only reads process information.
- Quit and Force Quit use the public `NSRunningApplication` API. They only work on apps that
  run as your user.
