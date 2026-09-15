# Contributing

## Reporting bugs

Open an issue with:

- the BaToHub version and the panel name and version;
- the command you ran and its exact output;
- the output of `BaToHub --status` and `BaToHub --check`;
- the last lines of `/var/log/batohub/batohub.log`.

Remove private keys, passwords and tokens before posting.

## Suggesting features

Describe the problem you want solved before describing the solution. If the request is about a new panel, include the panel's official repository, its install path, its systemd unit, its configuration file and how it handles certificates and subscription templates. The implementation is written from what those sources document, not from assumptions.

## Submitting patches

1. Fork the repository and work on a branch.
2. Keep the change focused; one subject per commit.
3. Run the repository checks before pushing:

```bash
bash scripts/checks.sh
```

4. Open a pull request describing the behaviour change and the verification you performed.

Patches are accepted under GPL-3.0. By submitting a patch you confirm that you have the right to license it under those terms and that the original copyright notice, project name and repository URL are preserved.

## Code style

- Bash, `set -Eeuo pipefail`, `local` in every function, quoted expansions.
- No `eval`, no execution of text fetched from the network other than the official panel installers, no pipe from `curl` into a shell.
- Temporary files and directories through `mktemp`.
- Shared state written under `flock`, atomically.
- No credentials, keys or tokens in logs, on command lines, or in the process list.
- shellcheck clean, shfmt formatted, `bash -n` clean.
- shellcheck directives only where a false positive cannot be avoided, each with a short reason.
- Comments explain why something is done, not what the next line does.

Repository checks:

```bash
bash -n path/to/file.sh     # syntax
shellcheck path/to/file.sh  # analysis
shfmt -d -i 2 .             # formatting
bash scripts/checks.sh      # everything, including text hygiene
```

## Commit messages

Conventional commits:

```
feat: add a panel module for X
fix: refuse to restore an archive with undeclared members
docs: describe the backup metadata file
security: verify the archive checksum before extraction
chore: format shell sources with shfmt
```

Keep the subject in the imperative, under 72 characters. Explain the reason in the body when it is not obvious.

## Pull request process

- One reviewer approval before merging into `main`.
- The CI workflow must pass: syntax, shellcheck, formatting, JSON metadata, interface checks and text hygiene.
- Behaviour changes need a note in `CHANGELOG.md` under the next version.
- Panel or tool changes must keep every documented interface function and run `BaToHub --validate` successfully.

## Attribution requirements

Every fork and redistribution must preserve the copyright notice, the project name BaToHub and the original repository URL. See section 22 of the README.

## Contact

**@DatPHP**
