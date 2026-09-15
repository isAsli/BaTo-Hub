# Support

## Where to get help

Support, bug reports and feature requests: **@DatPHP**

## What to include in a report

- BaToHub version: `BaToHub --version`
- Status summary: `BaToHub --status`
- Integrity result: `BaToHub --check`
- Panel name and version: `BaToHub --list-panels` and `BaToHub --panel NAME version`
- The exact command that failed, with its full output
- The last 100 lines of `/var/log/batohub/batohub.log`

Never send private keys, passwords, licence-free configuration values such as API tokens, or a full copy of a panel database. Describe what is exposed instead of pasting the secret.

## What is supported

- Installation, update and uninstall of BaToHub itself.
- Panel detection, status, panel updates and the menu in panels: Rebecca, Marzban, PasarGuard, 3X-UI (Sanaei) and VPN-UI.
- Certificate issuance, renewal and reporting for BaToHub-managed certificates.
- Subscription template apply, staging and removal.
- Backup, restore and import.
- The BaToHub update mechanism, including rollback.
- The Foxima tool integration.

## What is not supported

- Repairing a panel that was configured or damaged outside BaToHub.
- Recovering a database, a panel or a host that was lost outside BaToHub's backup flow.
- Managed hosting tasks, firewall policy, kernel tuning or proxy protocol configuration.
- Custom feature development for private or proprietary variants. Such requests are handled commercially through the contact above.
- Panels that are not shipped with this release.

## Before opening a request

1. Run `BaToHub --validate` and `BaToHub --check`.
2. Confirm the panel is detected: `BaToHub --detect`.
3. Search the log for the failing action: `grep -i error /var/log/batohub/batohub.log`.
4. For certificate failures, confirm the DNS record and that port 80 is free.

## Response expectations

- Initial reply: within 7 days.
- Requests are handled in the order received; security reports are handled first, as described in SECURITY.md.
- Support is provided on a best-effort basis by the maintainers. There is no service level agreement.
