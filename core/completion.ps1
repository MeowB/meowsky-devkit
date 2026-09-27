$meowskyCompleter = {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)


  $builtIns = @('.', './', 'help')
  foreach ($name in $script:MeowskyFeatureOrder) {
    $manifest = $script:MeowskyFeatures[$name]
    if ($manifest -and $name -ne 'workspace') {
      $builtIns += @($manifest.Command) + @($manifest.Aliases)
    }
  }
  foreach ($item in $builtIns) {
    if ($item -like "$wordToComplete*") {
      [System.Management.Automation.CompletionResult]::new($item, $item, 'ParameterValue', $item)
    }
  }

  $root = Get-WorkRoot -ExistingOnly
  if (-not $root) {
    return
  }

  Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$wordToComplete*" } |
    Sort-Object Name |
    ForEach-Object {
      $completionText = if ($_.Name -match '\s') { "'$($_.Name)'" } else { $_.Name }
      [System.Management.Automation.CompletionResult]::new($completionText, $_.Name, 'ParameterValue', $_.FullName)
    }
}


$meowskyTargetCompleter = {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
  $action = [string]$fakeBoundParameters.Action
  if (-not $action -and $commandAst.CommandElements.Count -ge 2) {
    $action = $commandAst.CommandElements[1].Extent.Text.Trim([char]39, [char]34)
  }
  $feature = $script:MeowskyCommands[$action.ToLowerInvariant()]
  if ($feature -and $feature.Completion) {
    & $feature.Completion $commandName $parameterName $wordToComplete $commandAst $fakeBoundParameters
  }
}
foreach ($commandName in @('meowsky', 'dev')) {
  Register-ArgumentCompleter -CommandName $commandName -ParameterName Action -ScriptBlock $meowskyCompleter
  Register-ArgumentCompleter -CommandName $commandName -ParameterName Target -ScriptBlock $meowskyTargetCompleter
}
