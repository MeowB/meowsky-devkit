# Terminal colors come from the active identity scheme. Reset SGR foreground/background
# to the terminal defaults rather than selecting a ConsoleColor/ANSI palette slot.
function Reset-MeowskyTerminalColors {
  [Console]::Write(([char]27).ToString() + '[39;49m')
}

function Enable-MeowskyTerminalDirectoryReporting {
  # Wrap once, preserving the prompt that was installed before Meowsky loaded.
  if ($global:MeowskyTerminalPromptInstalled) { return }
  $global:MeowskyTerminalOriginalPrompt = $function:prompt
  function global:prompt {
    # Invoke first so the original prompt sees the previous command's status.
    $meowskyPromptText = & $global:MeowskyTerminalOriginalPrompt
    $meowskyLocation = $executionContext.SessionState.Path.CurrentLocation
    if ($meowskyLocation.Provider.Name -eq 'FileSystem') {
      $meowskyPath = $meowskyLocation.ProviderPath
      if ($meowskyPath -notmatch '[\x00-\x1f\x7f]') {
        $Host.UI.Write("$([char]27)]9;9;`"$meowskyPath`"$([char]27)\")
      }
    }
    $meowskyPromptText
  }
  $global:MeowskyTerminalPromptInstalled = $true
}
