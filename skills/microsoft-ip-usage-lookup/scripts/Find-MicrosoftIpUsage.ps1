[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $IPAddress,

    [string] $AzureLocation,

    [ValidateSet('Worldwide', 'China', 'USGovDoD', 'USGovGCCHigh')]
    [string] $Microsoft365Instance = 'Worldwide',

    [string] $CacheDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) 'microsoft-ip-intelligence-cache'),

    [ValidateRange(1, 168)]
    [int] $CacheTtlHours = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SourceResult {
    param([string] $Name)
    [ordered]@{
        source = $Name
        status = 'unavailable'
        matches = @()
        retrievedAt = $null
        error = $null
    }
}

function Get-AddressInfo {
    param([string] $Value)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Value, [ref] $parsed)) {
        throw "Invalid IP address: $Value"
    }

    [ordered]@{
        address = $parsed.IPAddressToString
        family = if ($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { 'IPv4' } else { 'IPv6' }
        bytes = $parsed.GetAddressBytes()
        isPrivate = $false
        isReserved = $false
    }
}

function Test-CidrContains {
    param(
        [byte[]] $AddressBytes,
        [string] $Cidr
    )
    $parts = $Cidr.Split('/', 2)
    if ($parts.Count -ne 2) { return $false }
    $network = $null
    $prefixLength = 0
    if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref] $network)) { return $false }
    if (-not [int]::TryParse($parts[1], [ref] $prefixLength)) { return $false }
    $networkBytes = $network.GetAddressBytes()
    if ($networkBytes.Length -ne $AddressBytes.Length) { return $false }
    $maxPrefix = $AddressBytes.Length * 8
    if ($prefixLength -lt 0 -or $prefixLength -gt $maxPrefix) { return $false }

    $fullBytes = [math]::Floor($prefixLength / 8)
    $remainingBits = $prefixLength % 8
    for ($index = 0; $index -lt $fullBytes; $index++) {
        if ($AddressBytes[$index] -ne $networkBytes[$index]) { return $false }
    }
    if ($remainingBits -gt 0) {
        $mask = [byte](256 - [math]::Pow(2, 8 - $remainingBits))
        if (($AddressBytes[$fullBytes] -band $mask) -ne ($networkBytes[$fullBytes] -band $mask)) { return $false }
    }
    $true
}

function Get-ErrorText {
    param([System.Management.Automation.ErrorRecord] $ErrorRecord)
    if ($ErrorRecord.Exception.Message) { return $ErrorRecord.Exception.Message }
    $ErrorRecord.ToString()
}

function Get-OptionalProperty {
    param(
        [AllowNull()] $Object,
        [string] $Name
    )
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    $property.Value
}

function Get-CacheFilePath {
    param([string] $Name)
    $safeName = $Name -replace '[^A-Za-z0-9._-]', '_'
    Join-Path $CacheDirectory "$safeName.cache"
}

function Read-CacheFile {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $cacheAge = [DateTime]::UtcNow - (Get-Item -LiteralPath $Path).LastWriteTimeUtc
    if ($cacheAge.TotalHours -ge $CacheTtlHours) { return $null }
    try {
        Import-Clixml -LiteralPath $Path
    } catch {
        return $null
    }
}

function Write-CacheFile {
    param(
        [string] $Path,
        [AllowNull()] $Value
    )
    New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
    $temporaryPath = "$Path.$([guid]::NewGuid().Guid).tmp"
    $Value | Export-Clixml -LiteralPath $temporaryPath -Depth 20 -Force
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Read-JsonCacheFile {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $cacheAge = [DateTime]::UtcNow - (Get-Item -LiteralPath $Path).LastWriteTimeUtc
    if ($cacheAge.TotalHours -ge $CacheTtlHours) { return $null }
    try {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-JsonCacheFile {
    param(
        [string] $Path,
        [AllowNull()] $Value
    )
    New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
    $temporaryPath = "$Path.$([guid]::NewGuid().Guid).tmp"
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-CacheInfo {
    param([string] $Path)
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    [ordered]@{
        path = $Path
        used = $false
        expiresAt = if ($exists) { (Get-Item -LiteralPath $Path).LastWriteTimeUtc.AddHours($CacheTtlHours).ToString('o') } else { $null }
        ttlHours = $CacheTtlHours
    }
}

$addressInfo = Get-AddressInfo -Value $IPAddress
$retrievedAt = [DateTime]::UtcNow.ToString('o')
$result = [ordered]@{
    normalizedInput = [ordered]@{
        address = $addressInfo.address
        family = $addressInfo.family
        requestedAzureLocation = $AzureLocation
        microsoft365Instance = $Microsoft365Instance
    }
    azureServiceTags = New-SourceResult -Name 'Azure service tags (Get-AzNetworkServiceTag)'
    azureBgpCommunities = New-SourceResult -Name 'Azure BGP communities (Get-AzBgpServiceCommunity)'
    microsoft365 = New-SourceResult -Name 'Microsoft 365 endpoint JSON'
    retrievedAt = $retrievedAt
}

$serviceTagCachePath = Get-CacheFilePath -Name "azure-service-tags-$AzureLocation"
$bgpCommunityCachePath = Get-CacheFilePath -Name 'azure-bgp-service-communities'
$microsoft365CachePath = Join-Path $CacheDirectory "microsoft365-$Microsoft365Instance.json"
$result.azureServiceTags.cache = Get-CacheInfo -Path $serviceTagCachePath
$result.azureBgpCommunities.cache = Get-CacheInfo -Path $bgpCommunityCachePath
$result.microsoft365.cache = Get-CacheInfo -Path $microsoft365CachePath

if ($AzureLocation) {
    try {
        $serviceTagCache = Read-CacheFile -Path $serviceTagCachePath
        if ($null -ne $serviceTagCache) {
            $serviceTags = $serviceTagCache.data
            $serviceTagRetrievedAt = $serviceTagCache.retrievedAt
            $result.azureServiceTags.cache.used = $true
        } else {
            $serviceTags = Get-AzNetworkServiceTag -Location $AzureLocation
            $serviceTagRetrievedAt = [DateTime]::UtcNow.ToString('o')
            Write-CacheFile -Path $serviceTagCachePath -Value ([ordered]@{ retrievedAt = $serviceTagRetrievedAt; data = $serviceTags })
            $result.azureServiceTags.cache = Get-CacheInfo -Path $serviceTagCachePath
        }
        $matches = [System.Collections.Generic.List[object]]::new()
        foreach ($tag in @($serviceTags.Values)) {
            $properties = Get-OptionalProperty -Object $tag -Name 'Properties'
            $prefixes = @(Get-OptionalProperty -Object $properties -Name 'AddressPrefixes')
            foreach ($prefix in $prefixes) {
                if (Test-CidrContains -AddressBytes $addressInfo.bytes -Cidr $prefix) {
                    $matches.Add($tag.Name)
                }
            }
        }
        $result.azureServiceTags.status = if ($matches.Count) { 'Microsoft-published match' } else { 'no match in checked data' }
        $result.azureServiceTags.matches = @($matches)
        $result.azureServiceTags.retrievedAt = $serviceTagRetrievedAt
    } catch {
        $result.azureServiceTags.error = Get-ErrorText $_
    }
} else {
    $result.azureServiceTags.error = 'AzureLocation was not supplied; Get-AzNetworkServiceTag requires a location.'
}

if ($AzureLocation) {
    try {
        $bgpCommunityCache = Read-CacheFile -Path $bgpCommunityCachePath
        if ($null -ne $bgpCommunityCache) {
            $communities = $bgpCommunityCache.data
            $bgpRetrievedAt = $bgpCommunityCache.retrievedAt
            $result.azureBgpCommunities.cache.used = $true
        } else {
            $communities = Get-AzBgpServiceCommunity
            $bgpRetrievedAt = [DateTime]::UtcNow.ToString('o')
            Write-CacheFile -Path $bgpCommunityCachePath -Value ([ordered]@{ retrievedAt = $bgpRetrievedAt; data = $communities })
            $result.azureBgpCommunities.cache = Get-CacheInfo -Path $bgpCommunityCachePath
        }
        $matches = [System.Collections.Generic.List[object]]::new()
        foreach ($resource in @($communities)) {
            foreach ($community in @(Get-OptionalProperty -Object $resource -Name 'BgpCommunities')) {
                foreach ($prefix in @(Get-OptionalProperty -Object $community -Name 'CommunityPrefixes')) {
                    if (Test-CidrContains -AddressBytes $addressInfo.bytes -Cidr $prefix) {
                        $matches.Add([ordered]@{
                            serviceSupportedRegion = Get-OptionalProperty -Object $community -Name 'ServiceSupportedRegion'
                            communityName = Get-OptionalProperty -Object $community -Name 'CommunityName'
                            communityValue = Get-OptionalProperty -Object $community -Name 'CommunityValue'
                            matchedCidr = $prefix
                            isAuthorizedToUse = Get-OptionalProperty -Object $community -Name 'IsAuthorizedToUse'
                            serviceGroup = Get-OptionalProperty -Object $community -Name 'ServiceGroup'
                        })
                    }
                }
            }
        }
        $result.azureBgpCommunities.status = if ($matches.Count) { 'Microsoft-published match' } else { 'no match in checked data' }
        $result.azureBgpCommunities.matches = @($matches)
        $result.azureBgpCommunities.retrievedAt = $bgpRetrievedAt
    } catch {
        $result.azureBgpCommunities.error = Get-ErrorText $_
    }
} else {
    $result.azureBgpCommunities.error = 'AzureLocation was not supplied; Azure context is required for Get-AzBgpServiceCommunity.'
}

try {
    $microsoft365Cache = Read-JsonCacheFile -Path $microsoft365CachePath
    if ($null -ne $microsoft365Cache) {
        $version = $microsoft365Cache.version
        $endpointSets = @($microsoft365Cache.endpoints | ForEach-Object { $_ })
        $clientRequestId = $microsoft365Cache.clientRequestId
        $microsoft365RetrievedAt = $microsoft365Cache.retrievedAt
        $result.microsoft365.cache.used = $true
    } else {
        $clientRequestId = [guid]::NewGuid().Guid
        $versionUri = "https://endpoints.office.com/version/$Microsoft365Instance`?ClientRequestId=$clientRequestId"
        $version = Invoke-RestMethod -Uri $versionUri -Method Get
        $endpointUri = "https://endpoints.office.com/endpoints/$Microsoft365Instance`?ClientRequestId=$clientRequestId"
        $endpointSets = @(Invoke-RestMethod -Uri $endpointUri -Method Get)
        $microsoft365RetrievedAt = [DateTime]::UtcNow.ToString('o')
        Write-JsonCacheFile -Path $microsoft365CachePath -Value ([ordered]@{
            retrievedAt = $microsoft365RetrievedAt
            clientRequestId = $clientRequestId
            version = $version
            endpoints = $endpointSets
        })
        $result.microsoft365.cache = Get-CacheInfo -Path $microsoft365CachePath
    }
    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($endpoint in @($endpointSets)) {
        foreach ($prefix in @(Get-OptionalProperty -Object $endpoint -Name 'ips')) {
            if (Test-CidrContains -AddressBytes $addressInfo.bytes -Cidr $prefix) {
                $matches.Add([ordered]@{
                    id = Get-OptionalProperty -Object $endpoint -Name 'id'
                    serviceArea = Get-OptionalProperty -Object $endpoint -Name 'serviceArea'
                    serviceAreaDisplayName = Get-OptionalProperty -Object $endpoint -Name 'serviceAreaDisplayName'
                    category = Get-OptionalProperty -Object $endpoint -Name 'category'
                    required = Get-OptionalProperty -Object $endpoint -Name 'required'
                    expressRoute = Get-OptionalProperty -Object $endpoint -Name 'expressRoute'
                    tcpPorts = Get-OptionalProperty -Object $endpoint -Name 'tcpPorts'
                    udpPorts = Get-OptionalProperty -Object $endpoint -Name 'udpPorts'
                    matchedCidr = $prefix
                })
            }
        }
    }
    $result.microsoft365.status = if ($matches.Count) { 'Microsoft-published match' } else { 'no match in checked data' }
    $result.microsoft365.matches = @($matches)
    $result.microsoft365.instance = $version.instance
    $result.microsoft365.version = $version.latest
    $result.microsoft365.clientRequestId = $clientRequestId
    $result.microsoft365.retrievedAt = $microsoft365RetrievedAt
} catch {
    $result.microsoft365.error = Get-ErrorText $_
}

$result.azureServiceTags = [ordered]@{
    matches = @($result.azureServiceTags.matches)
    error = $result.azureServiceTags.error
}

$result.azureBgpCommunities = [ordered]@{
    matches = @($result.azureBgpCommunities.matches | ForEach-Object { $_.communityName })
    error = $result.azureBgpCommunities.error
}

$result.microsoft365.matches = @($result.microsoft365.matches | ForEach-Object {
    '{0}:{1}' -f $_.id, $_.serviceAreaDisplayName
})

$result.microsoft365 = [ordered]@{
    matches = @($result.microsoft365.matches)
    error = $result.microsoft365.error
}

[pscustomobject]$result | ConvertTo-Json -Depth 12