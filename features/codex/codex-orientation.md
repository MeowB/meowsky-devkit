# Project session context

Workspace root: $root
Today: $today

Top-level project tree:
$tree

Git status at startup:
$gitStatus

At launch, inspect README.md if present and relevant documentation for the task. Give a concise orientation: what the project does, its main folders and setup files, and its starting Git state. Treat this snapshot as startup context rather than live status.

For C development on Windows, read the Meowsky guide at `$cDevelopmentGuide` when the task calls for the established environment or daily workflow. It covers opening a workspace, editing in Neovim, compiling and running with GCC, debugging with GDB, and the relevant commands. The guide is in the devkit checkout, so use this absolute path even when the workspace is elsewhere.
