# java-format-scripts

Portable Bash tooling for installing and using [google-java-format](https://github.com/google/google-java-format).

## Install

The one-line installer downloads the versioned `java-format.sh` release asset to `~/.local/bin/java-format.sh`, then installs the latest google-java-format release for the current user.

```sh
curl -fsSL https://github.com/samzhu/java-format-scripts/releases/latest/download/install.sh | bash
```

The installer saves the script at a permanent path because `install-hook` records that path in the Git pre-commit hook. Do not run the main formatter only from a temporary directory.

To install a particular google-java-format version instead of its latest release:

```sh
curl -fsSL https://github.com/samzhu/java-format-scripts/releases/latest/download/install.sh | bash -s -- --version 1.35.0
```

To install a fixed version of this script, replace `latest` with a release tag such as `v1.0.0`:

```sh
curl -fsSL https://github.com/samzhu/java-format-scripts/releases/download/v1.0.0/install.sh | bash
```

`curl | bash` executes remote code. Review the tagged release before running it in environments you do not control.

## Commands

```sh
~/.local/bin/java-format.sh install [--version <x.y.z>] [--force]
~/.local/bin/java-format.sh format [path...]
~/.local/bin/java-format.sh diff [--staged | --base <git-ref>]
~/.local/bin/java-format.sh check [path...]
~/.local/bin/java-format.sh install-hook
~/.local/bin/java-format.sh uninstall-hook
```

- `format` recursively formats all `*.java` files below the supplied paths, excluding `.git`.
- `diff` formats every Java file in the unstaged Git diff; `--staged` formats only index content and preserves any unstaged changes to the same file.
- `check` exits nonzero if google-java-format would make a change.
- `install-hook` safely preserves an existing `pre-commit` hook and only updates staged Java blobs. `uninstall-hook` restores the prior hook.

## Platform support

- macOS Apple Silicon, Linux x64/arm64, and Windows x64 through Git Bash/MSYS/WSL use official native binaries.
- Intel Mac and other unsupported architectures use the all-deps JAR and require a JDK 21+.
- The script defaults to the newest google-java-format release. It records the known version when the script was released at the top of `java-format.sh`.

## Publishing a new script release

1. Update `RELEASE_TAG` in `install.sh` to the new tag, then update the README's fixed-version example if needed.
2. Commit and push the change, then create and push the tag.
3. Upload both shell files as assets with the same names:

   ```sh
   gh release create v1.0.0 java-format.sh install.sh --title v1.0.0 --generate-notes
   ```

The `latest` installation URL works because GitHub provides a stable URL for a release asset with a fixed filename.
