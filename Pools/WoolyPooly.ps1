﻿using module ..\Modules\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [PSCustomObject]$Params,
    [alias("WorkerName")]
    [String]$Worker,
    [TimeSpan]$StatSpan,
    [String]$DataWindow = "estimate_current",
    [Bool]$InfoOnly = $false,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10",
    [String]$StatAverageStable = "Week"
)

#https://api.woolypooly.com/api/stats
#https://communication.woolypooly.com/api/conversion/getcurrencies
#https://api.woolypooly.com/api/eth-1/blocks
#https://api.woolypooly.com/api/cfx-1/stats
$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pools_Request       = [PSCustomObject]@{}
try {
    $Pools_Request = Invoke-RestMethodAsync "https://api.woolypooly.com/api/stats" -tag $Name -timeout 15 -cycletime 120 -delay 250
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Log -Level Warn "Pool API ($Name) for $Pool_Currency has failed. "
    return
}

#$Result = (Invoke-WebRequest "https://woolypooly.com/js/app.5956a294.js").Content
#if ($Result -match "coins:({.+?}})}") {
#    $Tech = ConvertFrom-Json "$($Matches[1] -replace "!0","1" -replace "!1","0" -replace ":(\.\d)",':0$1' -replace "https:/", "httpsxxx" -replace "http:/", "httpxxx" -replace "([a-zA-Z0-9]+):",'"$1":' -replace "httpxxx","http:/" -replace "httpsxxx","https:/")"
#    $Tech.PSObject.Properties.Value | Sort-Object name | Foreach-Object {
#        $PoolHost = $_.servers[0].urls
#        "[PSCustomObject]@{symbol = `"$($_.name)`"; port = $($PoolHost -split ':' | Select-Object -Last 1); host = `"$($PoolHost -replace "\..+$")`"; rpc = `"$($PoolHost -replace "\..+$")-1`"}"
#    }
#}

$Pools_Data = @(
    [PSCustomObject]@{symbol = "AE";   port = 20000; host = "ae"; rpc = "aeternity-1"}
    [PSCustomObject]@{symbol = "AION"; port = 33333; host = "aion"; rpc = "aion-1"}
    [PSCustomObject]@{symbol = "ALPH"; port = 3106; host = "alph"; rpc = "alph-1"}
    [PSCustomObject]@{symbol = "CFX";  port = 3094; host = "cfx"; rpc = "cfx-1"}
    [PSCustomObject]@{symbol = "CTXC"; port = 40000; host = "cortex"; rpc = "cortex-1"}
    [PSCustomObject]@{symbol = "ERG";  port = 3100; host = "erg"; rpc = "ergo-1"}
    [PSCustomObject]@{symbol = "ETC";  port = 35000; host = "etc"; rpc = "etc-1"}
    [PSCustomObject]@{symbol = "ETF";  port = 3114; host = "ethf"; rpc = "ethf-1"}
    [PSCustomObject]@{symbol = "ETHW";  port = 3096; host = "ethw"; rpc = "ethw-1"}
    [PSCustomObject]@{symbol = "FIRO"; port = 3098; host = "firo"; rpc = "firo-1"}
    [PSCustomObject]@{symbol = "FLUX"; port = 3092; host = "zel"; rpc = "zel-1"}
    [PSCustomObject]@{symbol = "GRIN-PRI";  port = 12000; host = "grin"; rpc = "grin-1"}
    [PSCustomObject]@{symbol = "KAS"; port = 3112; host = "kas"; rpc = "kas-1"}
    [PSCustomObject]@{symbol = "MWC-PRI"; port = 11000; host = "mwc"; rpc = "mwc-1"}
    [PSCustomObject]@{symbol = "RTM"; port = 3110; host = "rtm"; rpc = "rtm-1"}
    [PSCustomObject]@{symbol = "RVN";  port = 55555; host = "rvn"; rpc = "raven-1"}
    [PSCustomObject]@{symbol = "VEIL"; port = 3098; host = "veil"; rpc = "veil-1"}
    [PSCustomObject]@{symbol = "VTC"; port = 3102; host = "vtc"; rpc = "vtc-1"}
    [PSCustomObject]@{symbol = "XMR"; port = 3108; host = "xmr"; rpc = "xmr-1"}
)

$Pool_PayoutScheme = "PPLNS"
$Pool_Region = Get-Region "eu"

$Pools_Data | Where-Object {$Pool_Currency = $_.symbol -replace "-.+$";$Pools_Request."$($_.rpc)" -and ($Wallets.$Pool_Currency -or $InfoOnly)} | ForEach-Object {
    $Pool_Coin      = Get-Coin $_.symbol
    $Pool_Port      = $_.port
    $Pool_RpcPath   = $_.rpc

    $Pool_Algorithm_Norm = Get-Algorithm $Pool_Coin.algo

    $Pool_EthProxy  = if ($Pool_Algorithm_Norm -match $Global:RegexAlgoHasEthproxy) {"qtminer"} else {$null}

    if (-not $InfoOnly) {
        $Pool_BlocksRequest = [PSCustomObject]@{}
        try {
            $Pool_BlocksRequest = (Invoke-RestMethodAsync "https://api.woolypooly.com/api/$($Pool_RpcPath)/blocks" -tag $Name -timeout 20 -cycletime 120 -delay 250).modes | Where-Object {$_.payoutScheme -eq $Pool_PayoutScheme}
        }
        catch {
            if ($Error.Count){$Error.RemoveAt(0)}
            Write-Log -Level Info "Pool blocks API ($Name) for $Pool_Currency has failed. "
        }

        $Pool_StatsRequest  = [PSCustomObject]@{}
        try {
            $Pool_StatsRequest  = (Invoke-RestMethodAsync "https://api.woolypooly.com/api/$($Pool_RpcPath)/stats?simple=false" -tag $Name -timeout 20 -cycletime 3600 -delay 250).modes | Where-Object {$_.payoutScheme -eq $Pool_PayoutScheme}
        }
        catch {
            if ($Error.Count){$Error.RemoveAt(0)}
            Write-Log -Level Info "Pool stats API ($Name) for $Pool_Currency has failed. "
        }

        $Pool_Data      = $Pools_Request.$Pool_RpcPath.modes | Where-Object {$_.payoutScheme -eq $Pool_PayoutScheme}
        $Pool_AlgoStats = if ($Pool_Data) {$Pool_Data.algo_stats.PSObject.Properties | Where-Object {$_.Name -eq "default" -or (Get-Algorithm $_.Name) -eq $Pool_Algorithm_Norm} | Foreach-Object {$_.Value}}

        $timestamp = Get-UnixTimestamp
        $timestamp24h = $timestamp - 86400

        $Pool_BlocksRequest_Completed = $Pool_BlocksRequest.matured | Where-Object {$_.timestamp -gt $timestamp24h -and -not $_.orphan -and ($_.algo -eq "default" -or (Get-Algorithm $_.Name) -eq $Pool_Algorithm_Norm)}

        $blocks_measure = $Pool_BlocksRequest_Completed | Measure-Object -Minimum -Maximum -Property timestamp
        $blocks_reward  = ($Pool_BlocksRequest_Completed | Measure-Object -Average -Property reward).Average
        $blocks_count   = $blocks_measure.Count

        if ($blocks_measure -and $Pool_BlocksRequest.immature -and $Pool_BlocksRequest.immature.Count) {
            $blocks_measure_immature = $Pool_BlocksRequest.immature | Where-Object {$_.timestamp -gt $timestamp24h} | Measure-Object -Minimum -Maximum -Property timestamp
            if ($blocks_measure_immature.Maximum -gt $blocks_measure.Maximum) {$blocks_measure.Maximum = $blocks_measure_immature.Maximum}
            if (-not $blocks_measure.Minimum) {$blocks_measure.Minimum = $blocks_measure_immature.Minimum}
            $blocks_count += (1-($Pool_BlocksRequest.rate | Select-Object -First 1).orphan) * $blocks_measure_immature.Count
        }

        $Pool_BLK       = $(if ($blocks_count -gt 1 -and ($blocks_measure.Maximum - $blocks_measure.Minimum)) {86400/($blocks_measure.Maximum - $blocks_measure.Minimum)} else {1})*$blocks_count
        $Pool_TSL       = $timestamp - (@($Pool_BlocksRequest.immature | Select-Object) + @($Pool_BlocksRequest.matured | Select-Object) | Measure-Object -Maximum -Property timestamp).Maximum
        $Pool_HR        = ($Pool_StatsRequest.perfomance | Where-Object {($_.algo -eq "default" -or (Get-Algorithm $_.Name) -eq $Pool_Algorithm_Norm) -and (Get-UnixTimestamp (Get-Date $_.created)) -ge $blocks_measure.Minimum} | Measure-Object -Average -Property poolHashrate).Average

        if (-not $Pool_HR) {$Pool_HR = ($Pool_StatsRequest.perfomance | Where-Object {$_.algo -eq "default" -or (Get-Algorithm $_.Name) -eq $Pool_Algorithm_Norm} | Measure-Object -Average -Property poolHashrate).Average}

        $btcPrice       = if ($Global:Rates.$Pool_Currency) {1/[double]$Global:Rates.$Pool_Currency} else {0}
        $btcRewardLive  = if ($Pool_HR) {$btcPrice * $blocks_reward * $Pool_BLK / $Pool_HR} else {0}

        $Stat = Set-Stat -Name "$($Name)_$($_.symbol)_Profit" -Value $btcRewardLive -Duration $StatSpan -ChangeDetection $false -HashRate $Pool_AlgoStats.hashrate -BlockRate $Pool_BLK -Quiet
        if (-not $Stat.HashRate_Live -and -not $AllowZero) {return}
    }

    foreach($Pool_SSL in @($false,$true)) {
        [PSCustomObject]@{
            Algorithm     = $Pool_Algorithm_Norm
		    Algorithm0    = $Pool_Algorithm_Norm
            CoinName      = $Pool_Coin.Name
            CoinSymbol    = $Pool_Currency
            Currency      = $Pool_Currency
            Price         = $Stat.$StatAverage #instead of .Live
            StablePrice   = $Stat.$StatAverageStable
            MarginOfError = $Stat.Week_Fluctuation
            Protocol      = "stratum+$(if ($Pool_SSL) {"ssl"} else {"tcp"})"
            Host          = "pool.woolypooly.com"
            Port          = $Pool_Port
            User          = "$($Wallets.$Pool_Currency).{workername:$Worker}"
            Pass          = "x"
            Region        = $Pool_Region
            SSL           = $Pool_SSL
            WTM           = -not $btcRewardLive
            Updated       = $Stat.Updated
            Workers       = $Pool_AlgoStats.minersTotal
            PoolFee       = $Pools_Request.$Pool_RpcPath.fee
            Hashrate      = $Stat.HashRate_Live
            TSL           = $Pool_TSL
            BLK           = $Stat.BlockRate_Average
            EthMode       = $Pool_EthProxy
            Name          = $Name
            Penalty       = 0
            PenaltyFactor = 1
            Disabled      = $false
            HasMinerExclusions = $false
            Price_0       = 0.0
            Price_Bias    = 0.0
            Price_Unbias  = 0.0
            Wallet        = $Wallets.$Pool_Currency
            Worker        = "{workername:$Worker}"
            Email         = $Email
        }
    }
}
