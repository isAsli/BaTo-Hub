# Contributing

Thanks for contributing to BaToHub.

## Reporting bugs

When reporting a bug, include:
- BaToHub version
- Operating system
- Panel involved, if any
- Exact steps to reproduce
- Any relevant log output
- What you expected to happen

## Suggesting features

Feature suggestions should include:
- The problem being solved
- Why the feature belongs in BaToHub
- Any relevant panel or workflow context

## Submitting patches

Patches must comply with GPL-3.0 in full. By submitting a patch you agree that the contribution may be used under GPL-3.0.

Patches must:
- Preserve the original copyright notice
- Preserve the project name BaToHub
- Preserve the original repository URL
- Pass `bash -n` on all shell files
- Pass `shellcheck` without warnings
- Pass `shfmt -d`
- Use conventional commit messages

## Code style

- Use `set -euo pipefail`
- Quote all variable expansions
- Use `local` in functions
- Use `mktemp` for temporary files
- Use `flock` around shared state when practical
- Do not use `eval` on external input
- Do not add network calls without a clear purpose
- Keep prompts and messages plain and professional

## Commit messages

Use conventional commits:
- `feat:` for new features
- `fix:` for bug fixes
- `refactor:` for internal changes
- `docs:` for documentation
- `chore:` for maintenance
- `security:` for security changes
- `test:` for tests

## Pull request process

1. Fork the repository
2. Create a branch
3. Make your changes
4. Run the checks above
5. Open a pull request
6. Keep the original project name and repository reference in any derived materials

## Attribution

Any use, modification, fork, or redistribution must comply with GPL-3.0 and must preserve the original copyright, the project name BaToHub, and the original repository URL. Custom or proprietary versions are not permitted under this license. Anyone needing a custom version should contact @DatPHP.

## Contact

For questions, contact @DatPHP.
