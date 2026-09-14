# BaToHub

BaToHub is a central server management system for BaTo server tools and integrations.

It is designed to be installed once on a server and extended over time with modules, tools, templates, updates, security checks, and panel-specific features.

The main interface is available through the global command:

```bash
BaToHub
```

It works from any directory and opens the same central menu.

## Current Features

- BaToHub core and central configuration
- Logging
- Integrity checks and update verification
- License/API validation hook for OpenLicense
- Update system via central manifest and optional GitHub release check
- Server information and status
- Tools menu with future-module placeholders
- License management
- Settings view
- Logs view
- Repair for common BaToHub issues
- Uninstall with confirmation

### Active Integration

- Rebecca
  - SSL management and renewal hook support
  - BaTo-Ui subscription template installation and removal
  - Status, update, and BaToHub change removal

### Not Active Yet

- PasarGuard integration
- Sanaei / 3X-UI integration

These modules may appear in the menu as future/unavailable items, but they do not claim to work until implemented and tested.

## Directory Layout

BaToHub keeps its managed files in one main directory:

```text
/opt/BaToHub/
├── bin/
├── core/
├── lib/
├── security/
├── modules/
│   └── rebecca/
│       ├── rebecca_core.sh
│       ├── ssl/
│       └── templates/
├── templates/
│   └── rebecca/
│       └── subscription/
└── VERSION
```

Global command:

```text
/usr/local/bin/BaToHub -> /opt/BaToHub/bin/BaToHub
```

Config and state:

```text
/etc/BaToHub/batohub.conf
/etc/BaToHub/integrity.sha256
/etc/BaToHub/license.json
/etc/BaToHub/.license_key
/var/lib/BaToHub
/var/log/BaToHub
```

## BaTo-Ui

BaTo-Ui is the Rebecca subscription page template provided by BaToHub.

It is Persian RTL, mobile-first, responsive, light/dark capable, and designed to work with Rebecca template variables.

Template source:

```text
/opt/BaToHub/templates/rebecca/subscription/index.html
```

After installation, BaToHub places the template in the configured Rebecca custom templates directory and sets the expected environment values.

Expected Rebecca environment values:

```text
CUSTOM_TEMPLATES_DIRECTORY=/opt/rebecca/bato-templates
SUBSCRIPTION_PAGE_TEMPLATE=subscription/index.html
```

Installed template:

```text
/opt/rebecca/bato-templates/subscription/index.html
```

BaTo-Ui displays subscription information such as username, status, traffic limit, used traffic, remaining traffic, expiration, subscription links, configuration links, QR codes, copy actions, client/download guidance, support link, and BaToHub branding.

Date handling is built to work with Unix timestamps, millisecond timestamps, ISO date strings, standard date/time strings, Persian digits, and Arabic digits.

## Rebecca SSL

The Rebecca SSL module is production-oriented and organized around the same safe workflow every time:

1. Ask for domain and email
2. Validate domain syntax
3. Check DNS resolution
4. Determine server public IP when possible
5. Compare DNS IP and server IP and report mismatches
6. Check whether required ports are available
7. Obtain a certificate
8. Store certificate and private key with restrictive permissions
9. Update Rebecca environment
10. Restart Rebecca safely
11. Verify the result
12. Provide renewal support via Certbot

Private keys are stored with restrictive permissions.

Private keys are never printed to the terminal and are not written into logs.

If port 80 is occupied, the reason is reported clearly.

Certbot or renewal errors are shown with enough detail to act on them.

## License System

BaToHub uses centralized license/API validation.

The product identifier is:

```text
batohub
```

License validation supports key, product, expiration, activation, machine fingerprint, hostname, version, and server-side status checks.

License-related errors use explicit codes such as:

- `invalid_key`
- `product_mismatch`
- `expired`
- `activation_limit`
- `server_error`
- `network_error`

When licensing is invalid or unavailable according to policy, the user is directed to:

```text
@BaTo_Help
```

License keys are not stored in world-readable files.

## Security

BaToHub emphasizes secure defaults:

- Restrictive file permissions for sensitive configuration and keys
- No unsafe `eval` of user input
- No execution of arbitrary text from remote sources
- Quoted variables
- Input validation and argument escaping
- Temporary files cleaned up where practical
- Integrity manifests and checksum verification
- Backups before destructive updates
- Log rotation and size awareness
- No passwords, private keys, or tokens written into logs

BaToHub detects tampering where practical through integrity manifests and remote version checks. It does not claim absolute tamper-proof protection, because a root user can still modify local files.

## Installation

You must run the installer as root.

Expected workflow:

```bash
chmod +x install.sh
./install.sh
```

After successful installation, run:

```bash
BaToHub
```

Installer responsibilities:

- Check root privileges
- Detect OS family where practical
- Install required dependencies when available
- Create the BaToHub directory tree
- Copy the application files
- Set restrictive permissions
- Install the global command
- Create initial configuration
- Initialize data and log directories
- Write integrity information
- Validate the setup
- Open BaToHub

If installation fails, the installer should report the failed step rather than leaving a vague half-installed state.

## Uninstall

BaToHub provides a safe uninstall flow.

Before removal:

- It shows what will be removed
- It asks for explicit confirmation
- It does not delete Rebecca itself just because BaToHub is removed
- It does not delete unrelated certificates or user data unless explicitly confirmed

## Update System

Updates are intended to affect BaToHub-managed files and explicitly documented external integration files only.

Before applying an update, the system should:

1. Validate the current installation
2. Create a backup
3. Download the update package
4. Verify checksum/signature
5. Validate the package structure
6. Validate the version
7. Apply the update
8. Remove obsolete files only when explicitly defined
9. Run migrations when necessary
10. Verify the result
11. Roll back if a critical step fails

Never overwrite the entire server based on a remote manifest alone.

## Update Manifest

The update manifest is expected at a configurable central URL, for example:

```text
https://bato.s2026h.space/batohub/manifest.json
```

Manifest information may include:

- Current version
- Package URL
- SHA-256
- Release notes
- Minimum supported version
- Required migrations
- Module versions
- Template versions

A package is never trusted solely because it came from the update server. Its checksum or signature must be verified.

## GitHub

BaToHub may use GitHub as a public source for releases and source code.

GitHub repository configuration is centralized. For example:

```text
BaToHub/BaToHub
```

GitHub release information may be checked, but it does not automatically override the central security and update validation system without verification.

## Configuration

Central configuration is maintained in one predictable location, for example:

```text
/etc/BaToHub/batohub.conf
```

Sensitive values use restrictive permissions.

Configuration includes values such as:

- Application name
- Application version
- License API
- Product ID
- Update manifest
- GitHub repository
- Support handle
- Channel handle
- Rebecca path
- Template root
- Data directory
- Log directory

Configuration values are not duplicated across many scripts.

## Logs

Logs are maintained under the BaToHub log directory.

Log entries include timestamp, module, action, success/failure, and useful error details.

Logs do not contain passwords, API keys, license keys, private keys, tokens, or full sensitive environment variables.

## Repair

The Repair section checks common BaToHub problems such as:

- Installation files
- Permissions
- Configuration
- Integrity
- Required commands
- Module state
- Rebecca state
- Template state
- SSL state
- License state
- Broken symlinks
- Missing directories

Repair does not blindly modify unrelated server components.

## Server Status

Status views provide concise summaries rather than raw command dumps.

Information may include:

- BaToHub version
- License status
- OS
- Architecture
- CPU and RAM context
- Disk usage
- Uptime context
- Rebecca status
- SSL status
- Template status
- Update status

Detailed logs should be available when needed.

## Versioning

BaToHub uses semantic-style versioning.

Current version file:

```text
/opt/BaToHub/VERSION
```

The displayed version should come from the central version source and not be duplicated manually across many files.

## Future Extensibility

The architecture is meant to allow future additions without rewriting the core, for example:

- New panel integrations
- New SSL providers
- New templates
- New server tools
- Monitoring
- Backup tools
- Security tools
- Network tools
- Database tools
- Automated maintenance
- More BaTo products

The current implementation does not pretend these features already exist.

## Release Package

Each release should contain:

- `VERSION`
- `README.md`
- `install.sh`
- `bin/`
- `core/`
- `lib/`
- `config/`
- `modules/`
- `templates/`
- `security/`

Release packages should be tested for integrity and accompanied by their SHA-256 when published.

## Support

Support:

```text
@BaTo_Help
```

Channel:

```text
@BaToHub
```

## License and Branding

Main project:

```text
BaToHub
```

Subscription template:

```text
BaTo-Ui
```
