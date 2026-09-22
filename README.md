# CheckMicrosoftIP

Private GitHub repository for the `microsoft-ip-usage-lookup` agent skill. The skill identifies Microsoft-published ranges containing an IPv4 or IPv6 address by checking Azure service tags, Azure BGP service communities, and Microsoft 365 endpoint data.

## Prerequisites

- GitHub CLI with `gh skill` support, authenticated to an account that can read this private repository.
- Windows PowerShell or PowerShell 7.
- For Azure results, the `Az.Network` module and an authenticated Azure session.
- Network access to `https://endpoints.office.com` for Microsoft 365 results.

## Preview

Private repositories are not returned by `gh skill search`. Specify this repository directly:

```powershell
gh skill preview kongou-ae/CheckMicrosoftIP microsoft-ip-usage-lookup@v0.1.0
```

## Install

Install for GitHub Copilot in the current project:

```powershell
gh skill install kongou-ae/CheckMicrosoftIP microsoft-ip-usage-lookup@v0.1.0 --agent github-copilot --scope project
```

Install for GitHub Copilot at user scope:

```powershell
gh skill install kongou-ae/CheckMicrosoftIP microsoft-ip-usage-lookup@v0.1.0 --agent github-copilot --scope user
```

The repository contains the skill under [`skills/microsoft-ip-usage-lookup`](./skills/microsoft-ip-usage-lookup/). The lookup script retrieves current source data at runtime and caches responses in the system temporary directory for 24 hours by default.

## Publish

Validate and publish a new release from the repository root:

```powershell
gh skill publish --dry-run
gh skill publish --tag v0.1.0
```