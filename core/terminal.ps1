# Terminal colors come from the active identity scheme. Reset SGR foreground/background
# to the terminal defaults rather than selecting a ConsoleColor/ANSI palette slot.
function Reset-MeowskyTerminalColors {
  [Console]::Write(([char]27).ToString() + '[39;49m')
}
