@{
    Name = 'refactor'
    Command = 'refactor'
    Aliases = @()
    EntryPoint = 'refactor.ps1'
    Handler = 'Invoke-MeowskyRefactorFeature'
    Help = 'help.txt'
    Description = 'Check audit and review prerequisites for selected refactoring'
    SkipWorkRoot = $true
    AcceptsArguments = $true
}
