# Security policy

## Reporting a vulnerability

Send vulnerability reports to **@DatPHP**. Include:

- the BaToHub version (`BaToHub --version`);
- the affected file or command;
- the steps that reproduce the problem;
- the impact you believe it has;
- a proposed fix if you have one.

Do not open a public issue for a vulnerability before it has been reviewed. Do not include private keys, passwords or tokens in a report; describe the exposure instead.

## Scope

In scope:

- the BaToHub source code, its installer, the uninstaller and the release scripts;
- the panel and tool modules shipped in this repository;
- the backup, restore and import flows;
- the self-update flow, including rollback;
- file permissions applied by BaToHub;
- handling of certificates and private keys managed by BaToHub.

Out of scope:

- the panels themselves and their official installers;
- vulnerabilities in acme.sh, curl, systemd, or the Linux kernel;
- misconfiguration of a panel performed outside BaToHub;
- servers where another administrator already has root access and rewrites BaToHub files;
- physical access to the server.

## Supported versions

Security fixes are applied to the latest release on the `main` branch. Older releases are not maintained. Upgrade with `BaToHub --update`.

## How releases are verified

Release archives are published together with a SHA-256 checksum file:

```bash
sha256sum BaToHub-0.0.3.zip
cat BaToHub-0.0.3.zip.sha256
```

`manifest.json` carries the version, the panel and tool list, and a SHA-256 for every managed file.

GPG signing is supported by `scripts/build-release.sh` through the `--gpg-key` option, and by the release workflow when a `SIGNING_KEY` secret is configured in the repository. Signatures are verified before they are published. When no key is configured, the release carries SHA-256 checksums only and no signature is claimed anywhere in the documentation or the release notes.

Verify a signature when a `.asc` file is published:

```bash
gpg --verify manifest.json.asc manifest.json
```

## What BaToHub does not claim

- BaToHub does not prevent a root user from modifying files on the same server. The integrity manifest detects changes between a recorded state and the current files, and reports them.
- The update mechanism trusts the configured GitHub repository over HTTPS. An attacker who can control that repository or the account that publishes it can publish a different tree. Signing the manifest narrows this to key custody.
- The panel installers that BaToHub downloads are executed as supplied by their authors. They are not reviewed by this project.
- BaToHub has not undergone an independent security audit or a penetration test.

## Response timeline

- Acknowledgement of a report: within 7 days.
- Initial assessment: within 14 days.
- Fix or mitigation plan: within 30 days for issues that affect confidentiality, integrity or availability of a supported installation.

There is no bug bounty program at this time.
