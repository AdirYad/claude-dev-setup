@{
    # Stylistic rules that don't fit a single-file, colored, interactive
    # installer script. Correctness rules (parse errors, unused vars,
    # automatic-variable assignment, positional params, etc.) stay enabled.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                     # a CLI installer prints to the host on purpose
        'PSUseShouldProcessForStateChangingFunctions', # internal helpers, not exported cmdlets
        'PSUseSingularNouns',                         # e.g. Install-Extensions reads better plural
        'PSReviewUnusedParameter',                   # false positive: script params are used inside nested functions
        'PSAvoidUsingPositionalParameters'           # our own tiny Write-* helpers read fine positionally
    )
}
