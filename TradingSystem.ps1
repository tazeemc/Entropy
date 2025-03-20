# TradingSystem.ps1
param(
    [string]$symbol = "NU",
    [double]$baseTemp = 25.0,
    [double]$maxHeat = 80.0,
    [double]$initialEquity = 100000.0
)

function Get-MarketData {
    param([string]$symbol)
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/$symbol"
    $response = Invoke-RestMethod -Uri $url
    return $response.chart.result[0]
}

function Calculate-MovingAverages {
    param([array]$prices, [int]$shortPeriod = 20, [int]$longPeriod = 50)
    $ma20 = ($prices | Select-Object -Last $shortPeriod | Measure-Object -Average).Average
    $ma50 = ($prices | Select-Object -Last $longPeriod | Measure-Object -Average).Average
    return @{
        ShortMA = $ma20
        LongMA = $ma50
    }
}

function Calculate-Momentum {
    param([array]$prices, [int]$period = 14)
    $current = $prices[-1]
    $past = $prices[-$period]
    return (($current - $past) / $past) * 100
}

function Calculate-RSI {
    param([array]$prices, [int]$period = 14)
    $gains = @()
    $losses = @()
    
    for($i = 1; $i -lt $prices.Count; $i++) {
        $change = $prices[$i] - $prices[$i-1]
        if($change -gt 0) {
            $gains += $change
            $losses += 0
        } else {
            $gains += 0
            $losses += [Math]::Abs($change)
        }
    }
    
    $gains = $gains | Select-Object -Last $period
    $losses = $losses | Select-Object -Last $period
    
    $avgGain = ($gains | Measure-Object -Average).Average
    $avgLoss = ($losses | Measure-Object -Average).Average
    
    if($avgLoss -eq 0) { return 100 }
    
    $rs = $avgGain / $avgLoss
    return 100 - (100 / (1 + $rs))
}

function Calculate-Temperature {
    param([array]$returns, [int]$window = 20)
    $volatility = $returns | Select-Object -Last $window
    $mean = ($volatility | Measure-Object -Average).Average
    $sumSquares = ($volatility | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum
    $std = [Math]::Sqrt($sumSquares / ($window - 1))
    return $std * [Math]::Sqrt(252)
}

function Calculate-Entropy {
    param([array]$returns, [int]$bins = 50)
    $hist = @{}
    $min = ($returns | Measure-Object -Minimum).Minimum
    $max = ($returns | Measure-Object -Maximum).Maximum
    $binWidth = ($max - $min) / $bins
    
    foreach($r in $returns) {
        $bin = [Math]::Floor(($r - $min) / $binWidth)
        if($hist.ContainsKey($bin)) { $hist[$bin]++ } 
        else { $hist[$bin] = 1 }
    }
    
    $total = $returns.Count
    $entropy = 0
    foreach($count in $hist.Values) {
        $prob = $count / $total
        $entropy -= $prob * [Math]::Log($prob + 1e-10)
    }
    return $entropy
}

function Calculate-PositionSize {
    param(
        [double]$equity,
        [double]$temperature,
        [double]$entropy,
        [double]$heat,
        [double]$momentum
    )
    
    $tempRatio = $baseTemp / $temperature
    $entropyFactor = [Math]::Exp(-$entropy / 2)
    $heatFactor = 1 - ($heat / $maxHeat)
    $momentumFactor = if($momentum -gt 0) { 1 + ($momentum / 100) } else { 1 / (1 + [Math]::Abs($momentum) / 100) }
    
    $baseSize = $equity * 0.01
    return [Math]::Min($baseSize * [Math]::Pow($tempRatio, 2) * $entropyFactor * $heatFactor * $momentumFactor, $equity * 0.02)
}

function Get-MarketRecommendation {
    param(
        [double]$temperature,
        [double]$entropy,
        [double]$baseTemp,
        [bool]$trendUp,
        [double]$momentum,
        [double]$rsi
    )
    
    if ($temperature -gt ($baseTemp * 1.5) -or $entropy -gt 0.8) { return "OUT" }
    if ($temperature -lt ($baseTemp * 0.75) -and $entropy -lt 0.3) {
        if ($trendUp -and $momentum -gt 0 -and $rsi -gt 30 -and $rsi -lt 70) { return "IN" }
    }
    return "NEUTRAL"
}

# Main execution
$data = Get-MarketData -symbol $symbol
$prices = $data.indicators.quote[0].close
$returns = $prices | ForEach-Object {
    if($previous) {
        $return = ($_ - $previous) / $previous
        $previous = $_
        return $return
    }
    $previous = $_
    return 0
}

$movingAverages = Calculate-MovingAverages -prices $prices
$momentum = Calculate-Momentum -prices $prices
$rsi = Calculate-RSI -prices $prices
$temperature = Calculate-Temperature -returns $returns
$entropy = Calculate-Entropy -returns $returns
$trendUp = $movingAverages.ShortMA -gt $movingAverages.LongMA
$positionSize = Calculate-PositionSize -equity $initialEquity -temperature $temperature -entropy $entropy -heat 0 -momentum $momentum
$recommendation = Get-MarketRecommendation -temperature $temperature -entropy $entropy -baseTemp $baseTemp -trendUp $trendUp -momentum $momentum -rsi $rsi

@{
    Symbol = $symbol
    Price = $prices[-1]
    Temperature = $temperature
    Entropy = $entropy
    PositionSize = $positionSize
    TempStatus = if($temperature -gt ($baseTemp * 1.5)) {"HIGH"} elseif($temperature -lt ($baseTemp * 0.75)) {"LOW"} else {"MEDIUM"}
    EntropyStatus = if($entropy -gt 0.8) {"HIGH"} elseif($entropy -lt 0.3) {"LOW"} else {"MEDIUM"}
    Trend = if($trendUp) {"UP"} else {"DOWN"}
    Momentum = $momentum
    RSI = $rsi
    Recommendation = $recommendation
    MA20 = $movingAverages.ShortMA
    MA50 = $movingAverages.LongMA
} | ConvertTo-Json