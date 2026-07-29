# java-format-scripts

Portable Bash tooling for installing and using [google-java-format](https://github.com/google/google-java-format).

## Install / 安裝

### Install the latest version / 安裝最新版

The one-line installer downloads the versioned `java-format.sh` release asset to `~/.local/bin/java-format.sh`, then installs the latest google-java-format release for the current user.

這行指令會下載已發佈版本的 `java-format.sh` 到 `~/.local/bin/java-format.sh`，再為目前使用者安裝最新版的 google-java-format。

```sh
curl -fsSL https://github.com/samzhu/java-format-scripts/releases/latest/download/install.sh | bash
```

The installer saves the script at a permanent path because `install-hook` records that path in the Git pre-commit hook. Do not run the main formatter only from a temporary directory.

安裝程式會把腳本存放在固定路徑，因為 `install-hook` 會將該路徑寫入 Git pre-commit hook。請勿只從暫存目錄執行主腳本。

### Pin google-java-format / 指定 google-java-format 版本

To install a particular google-java-format version instead of its latest release:

若不想安裝最新版，可在一鍵安裝指令最後指定 google-java-format 的版本：

```sh
curl -fsSL https://github.com/samzhu/java-format-scripts/releases/latest/download/install.sh | bash -s -- --version 1.35.0
```

### Pin this installer / 指定本工具版本

To install a fixed version of this script, replace `latest` with a release tag such as `v1.0.1`:

若要固定此工具本身的版本，請把 `latest` 改成 Release tag，例如 `v1.0.1`：

```sh
curl -fsSL https://github.com/samzhu/java-format-scripts/releases/download/v1.0.1/install.sh | bash
```

`curl | bash` executes remote code. Review the tagged release before running it in environments you do not control.

`curl | bash` 會直接執行遠端程式碼；在非自行控制的環境執行前，請先檢閱指定版本的 Release 內容。

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
   gh release create v1.0.1 java-format.sh install.sh --title v1.0.1 --generate-notes
   ```

The `latest` installation URL works because GitHub provides a stable URL for a release asset with a fixed filename.
