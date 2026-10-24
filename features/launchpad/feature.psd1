@{
    Name = 'launchpad'
    Command = 'launchpad'
    Aliases = @()
    EntryPoint = 'launchpad.ps1'
    Handler = 'Invoke-MeowskyLaunchpadFeature'
    Help = 'help.txt'
    Description = 'Open the software opportunity workspace'
    SkipWorkRoot = $true
}
