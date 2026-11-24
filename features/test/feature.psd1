@{
    Name = 'test'
    Command = 'test'
    Aliases = @()
    EntryPoint = 'test.ps1'
    Handler = 'Invoke-MeowskyTestFeature'
    Help = 'help.txt'
    Description = 'Test a compiled program against expected stdout'
    SkipWorkRoot = $true
    AcceptsArguments = $true
}
