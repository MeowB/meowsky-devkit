@{
    Name = 'refactor'
    Command = 'refactor'
    Aliases = @()
    EntryPoint = 'refactor.ps1'
    Handler = 'Invoke-MeowskyRefactorFeature'
    Help = 'help.txt'
    Description = 'Plan, approve, execute, and verify selected reviewed refactoring'
    SkipWorkRoot = $true
    AcceptsArguments = $true
}
