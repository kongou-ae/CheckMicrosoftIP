# Limitations and attribution boundaries

- Azure service tags are published network ranges. A range can cover multiple services, tenants, or customers. A broad tag such as `AzureCloud` is not tenant-specific.
- Microsoft 365 endpoint records describe network connectivity for a workload or service area. They do not identify the exact workload or customer using a connection from one IP.
- A CIDR match is not proof of current assignment. Addresses can be reallocated, aggregated, announced through another path, or used behind NAT, CDN, Front Door, or other intermediaries.
- BGP communities are attributes on route advertisements. They are not permanent properties of an IP address. `Get-AzBgpServiceCommunity` provides Microsoft-published mappings, but a private ExpressRoute advertisement will not necessarily be visible to public observers.
- Public route collectors, if consulted, are independent observations. They may be stale, filtered, incomplete, or show a different point of view. Keep them separate from Microsoft-published matches.
- WHOIS/RDAP, AS numbers, reverse DNS, and geolocation can corroborate registration or naming only. They cannot establish Microsoft service use or a BGP community.
- `no match in checked data` means only that the address was absent from the retrieved publication/version. It does not establish that the address is not Microsoft-owned or Microsoft-used.
- Private, loopback, link-local, multicast, documentation, and other reserved addresses generally cannot be attributed using public Microsoft service ranges.
- IPv6 and national-cloud results depend on the selected source and instance. Do not silently mix Azure clouds or Microsoft 365 instances.
- If Azure authentication, `Az.Network`, the requested location, or network access is unavailable, report `unavailable` for that source instead of using stale data or guessing.