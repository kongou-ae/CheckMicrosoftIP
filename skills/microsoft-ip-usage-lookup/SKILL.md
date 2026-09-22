---
name: microsoft-ip-usage-lookup
description: "Use when identifying what Microsoft usage an IP address or CIDR belongs to, including Azure service tags, Azure PowerShell BGP communities, ExpressRoute, or Microsoft 365 JSON endpoints."
argument-hint: "Enter an IPv4 or IPv6 address, optionally with an Azure location/cloud or Microsoft 365 instance."
---

# Microsoft IP Intelligence

Determine which Microsoft-published network purpose contains an IP address. Treat every result as evidence about a published network range, not proof of a specific tenant, resource, or current assignment.

## Run the lookup

Use the bundled [Find-MicrosoftIpUsage.ps1](./scripts/Find-MicrosoftIpUsage.ps1) script and parse its JSON output. Run it from PowerShell in an authenticated Azure session when Azure results are required:

```powershell
./scripts/Find-MicrosoftIpUsage.ps1 -IPAddress <ip> -AzureLocation <location>
```

For Microsoft 365-only lookup, omit `-AzureLocation`. Use `-Microsoft365Instance` for `Worldwide`, `China`, `USGovDoD`, or `USGovGCCHigh`. The script stores API/cmdlet responses under the system temporary directory in `microsoft-ip-intelligence-cache` and reuses each cache file for 24 hours. Override this with `-CacheDirectory` or `-CacheTtlHours` when needed. Do not replace the script with a static local IP database.

Keep the bundled files in these paths relative to this `SKILL.md`:

- `./scripts/Find-MicrosoftIpUsage.ps1`: lookup script.
- `./references/sources.md`: authoritative source documentation.
- `./references/limitations.md`: attribution and interpretation limitations.

## Workflow

1. Parse the script JSON, but do not expose the raw JSON in the normal chat response. Use the compact response format below. For Azure service tags, the script returns only `azureServiceTags.matches` and `azureServiceTags.error`. Treat `unavailable` and `no match in checked data` differently for the other sources.
2. Use `cache.used`, `cache.path`, `cache.expiresAt`, and `cache.ttlHours` internally. Mention caching only when relevant to freshness or troubleshooting; do not normally show cache paths, GUIDs, or raw retrieval metadata.
3. The script parses and normalizes one IPv4 or IPv6 address. It rejects malformed input and identifies private, loopback, link-local, multicast, documentation, and other reserved addresses before querying public Microsoft data.
4. Establish scope. Use the requested Azure `Location` and Microsoft 365 `Instance`; the script defaults Microsoft 365 to `Worldwide` but does not invent an Azure location.
5. The script checks Azure service tags with Azure PowerShell:

   ```powershell
   $serviceTags = Get-AzNetworkServiceTag -Location <location>
   ```

   `Location` is a reference for the service-tag version and cloud, not a regional filter. For each item in `$serviceTags.Values`, compare the normalized IP with `Properties.AddressPrefixes`. The JSON output's `azureServiceTags.matches` is an array containing only the matching `tagName` strings, including broad tags such as `AzureCloud`.

6. The script checks Azure BGP communities with Azure PowerShell:

   ```powershell
   $communities = Get-AzBgpServiceCommunity
   ```

   Compare the IP with each `BgpCommunities.CommunityPrefixes`. The JSON output's `azureBgpCommunities.matches` is an array containing only the matching `communityName` strings. Explain that a BGP community is a route attribute used for Azure/ExpressRoute classification, not an intrinsic ownership property of an IP.

7. The script checks Microsoft 365 JSON endpoints. On a cache miss it generates a fresh GUID for `ClientRequestId`, calls the version endpoint, saves the response together with the endpoint response, and then uses both saved responses for 24 hours. On a cache hit it makes no Microsoft 365 API call:

   ```text
   https://endpoints.office.com/version/<Instance>?ClientRequestId=<GUID>
   https://endpoints.office.com/endpoints/<Instance>?ClientRequestId=<GUID>
   ```

   Valid instances are `Worldwide`, `China`, `USGovDoD`, and `USGovGCCHigh`. Compare the IP with every `ips` CIDR. The final JSON output's `microsoft365` contains only `matches` and `error`; each `matches` entry is a string in the format `<id>:<serviceAreaDisplayName>`. Include `Common` dependencies. If several endpoint sets match, preserve all of them.

8. Classify each source independently as one of:
   - `Microsoft-published match`: the IP is contained in the source's published CIDR.
   - `no match in checked data`: the checked source was available and had no containing CIDR.
   - `unavailable`: the source could not be queried, for example because Azure context, `Az.Network`, or network access is missing.
   - `observed routing evidence`: an optional independent route observation, never a substitute for Microsoft-published data.

9. Return only this compact chat format unless the user asks for details:

   ```text
   ## <IP address>
   
   ### ServiceTag
   - <every matched service tag, one per line>
   - 一致なし / 取得不可
   
   ### BgpCommunity
   - <every matched BGP community, one per line>
   - 一致なし / 取得不可
   
   ### Microsoft 365
   - <every matched id:serviceAreaDisplayName, one per line>
   - 一致なし / 取得不可
   ```

   Use exactly the three headings `ServiceTag`, `BgpCommunity`, and `Microsoft 365`. Under each heading, list every match returned by the script, one per line. Never select only a representative match, omit broad tags such as `AzureCloud`, collapse multiple endpoint sets, or remove duplicate matches. For Microsoft 365, format every match as `id:serviceAreaDisplayName`. Show `一致なし` or `取得不可` only when applicable. Omit cache paths, request IDs, and change numbers from the normal response. Add one short caveat that a match identifies a Microsoft-published range, not a specific tenant or resource.

## Error and evidence rules

- If `Get-AzNetworkServiceTag` fails, state the exact missing prerequisite or error category and do not replace it with a stale local range database.
- If `Get-AzBgpServiceCommunity` fails, mark BGP data unavailable. Do not infer a community from AS 12076, WHOIS/RDAP, reverse DNS, or geolocation.
- Microsoft 365 version data is cached for 24 hours by default. On an endpoint-service `429`, do not retry repeatedly; report the rate limit and use no unverified result.
- This script's default cache TTL is 24 hours. When a cache expires, the next run refreshes the source and atomically replaces its cache file. A failed refresh does not silently use an expired cache.
- A negative result means only that the address was absent from the checked publication/version. It does not prove that Microsoft does not own or use the address.
- Never claim customer, tenant, subscription, resource, or exclusive service ownership from a CIDR match. See [limitations](./references/limitations.md).

## Sources

Use the official source details in [sources](./references/sources.md). Do not bundle current IP ranges in this skill; fetch them at lookup time.