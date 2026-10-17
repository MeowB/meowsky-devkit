@{
    Name = 'review'
    Command = 'review'
    Aliases = @()
    EntryPoint = 'review.ps1'
    Handler = 'Invoke-MeowskyReviewFeature'
    Help = 'help.txt'
    Description = 'Check whether a local audit is ready for semantic review'
    SkipWorkRoot = $true
    AcceptsArguments = $true
}
