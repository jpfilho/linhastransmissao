Get-ChildItem -Path "C:\aplicativos\fotos_h\lib" -Recurse -Filter "*.dart" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    if ($content -match "cell_tower") {
        $content = $content -replace "Icons\.cell_tower_rounded", "Icons.electric_bolt_rounded"
        $content = $content -replace "Icons\.cell_tower", "Icons.electric_bolt"
        Set-Content $_.FullName -Value $content -NoNewline
        Write-Host "Updated: $($_.Name)"
    }
}
