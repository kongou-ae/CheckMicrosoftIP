# Authoritative sources

## Azure service tags

- Cmdlet: [Get-AzNetworkServiceTag](https://learn.microsoft.com/en-us/powershell/module/az.network/get-aznetworkservicetag)
- Overview: [Azure service tags](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview)
- Command: `Get-AzNetworkServiceTag -Location <location>`
- Important fields: parent `Cloud` and `ChangeNumber`; each `Values` item has `Name`, `Properties.SystemService`, optional `Properties.Region`, `Properties.AddressPrefixes`, and `Properties.ChangeNumber`.
- The location parameter determines the reference version and the cloud associated with the Azure context. It does not limit prefixes to that region.
- If PowerShell authentication is available, use the cmdlet on a cache miss rather than an unauthenticated source. Current ranges must not be committed to the repository.
- The script caches the cmdlet response as a local CLIXML file for 24 hours by default. The cache is keyed by Azure location and the output reports whether it was used.

## Azure BGP service communities

- Cmdlet: [Get-AzBgpServiceCommunity](https://learn.microsoft.com/en-us/powershell/module/az.network/get-azbgpservicecommunity)
- Command: `Get-AzBgpServiceCommunity`
- Important fields: `BgpCommunities[].ServiceSupportedRegion`, `CommunityName`, `CommunityValue`, `CommunityPrefixes`, `IsAuthorizedToUse`, and `ServiceGroup`.
- `CommunityPrefixes` are the prefixes to compare with the input IP. `CommunityValue` is the BGP community value, commonly represented as an AS/value pair.
- Use this as Microsoft-published ExpressRoute/Azure route classification data. It does not prove that a route is currently visible from every network.
- The script caches the cmdlet response as a local CLIXML file for 24 hours by default and reuses it for matching until the TTL expires.

## Microsoft 365 JSON

- Documentation: [Microsoft 365 IP Address and URL web service](https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-ip-web-service?view=o365-worldwide)
- Service root: `https://endpoints.office.com`
- Version: `/version/<Instance>?ClientRequestId=<GUID>`
- Endpoints: `/endpoints/<Instance>?ClientRequestId=<GUID>`
- Supported instances: `Worldwide`, `China`, `USGovDoD`, and `USGovGCCHigh`.
- Generate a unique `ClientRequestId`. Check the version before downloading endpoint data and normally poll no more than once per hour.
- Endpoint records expose `id`, `serviceArea`, `serviceAreaDisplayName`, `ips`, `category`, `required`, `expressRoute`, `tcpPorts`, and `udpPorts`.
- Endpoint data is updated monthly with occasional out-of-band updates. The endpoint service can return HTTP 429; wait rather than repeatedly retrying.
- When a range appears in multiple categories, Microsoft recommends the highest priority category: `Optimize`, then `Allow`, then `Default`.
- The script caches the version and endpoint JSON responses together per instance for 24 hours by default. It does not call the Microsoft 365 API again while that cache is valid. The cache directory can be changed with `-CacheDirectory`.