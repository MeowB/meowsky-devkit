@{
    Name = 'animate'
    Command = 'animate'
    Aliases = @()
    EntryPoint = 'animate.ps1'
    Handler = 'Invoke-MeowskyAnimateFeature'
    Help = 'help.txt'
    Description = 'Run a terminal animation'
    SkipWorkRoot = $true
    AcceptsArguments = $true
}
