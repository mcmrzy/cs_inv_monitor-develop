# 分块并行下载 u2net.onnx（ghfast.top 单连接 ~43MB 截断，分 8 段绕过）
$ErrorActionPreference = "Stop"
$url = "https://ghfast.top/https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"
$out = "C:\Users\29538\.u2net\u2net.onnx"
$tmp = "C:\Users\29538\.u2net\_chunks"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
# 先 HEAD 获取总大小
$head = curl -s -I -L -m 30 $url
$len = 0
foreach ($l in $head) { if ($l -match '^content-length:\s*(\d+)') { $len = [long]$Matches[1] } }
if ($len -eq 0) { $len = 176394235 }
Write-Output "TOTAL: $len"
$n = 8
$chunk = [math]::Ceiling($len / $n)
$jobs = @()
for ($i = 0; $i -lt $n; $i++) {
    $start = $i * $chunk
    $end = [math]::Min($len - 1, $start + $chunk - 1)
    $f = "$tmp\chunk$i.bin"
    $js = Start-Job -ArgumentList $url, $f, $start, $end {
        param($u, $f, $s, $e)
        & curl -s -L -m 300 -r "$s-$e" -o $f $u
        return (Get-Item $f).Length
    }
    $jobs += $js
}
foreach ($j in $jobs) { Wait-Job $j | Out-Null }
$total = 0
foreach ($j in $jobs) {
    $sz = Receive-Job $j
    Write-Output "job $($j.Id): $sz"
    $total += $sz
}
Write-Output "TOTAL-DL: $total"
# 合并
$fs = [System.IO.File]::Open($out, [System.IO.FileMode]::Create)
for ($i = 0; $i -lt $n; $i++) {
    $b = [System.IO.File]::ReadAllBytes("$tmp\chunk$i.bin")
    $fs.Write($b, 0, $b.Length)
}
$fs.Close()
Write-Output "MERGED: $((Get-Item $out).Length)"
