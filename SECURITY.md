# Security Policy

## Reporting a vulnerability

Please **do not report security vulnerabilities through public GitHub Issues or pull requests**.

Use GitHub's private vulnerability reporting for this repository:

1. Open the repository's **Security and quality** tab.
2. Open **Advisories**.
3. Choose **Report a vulnerability**.

The repository includes a structured private vulnerability-report form to collect the information needed for triage.

If private vulnerability reporting is not available, use a private contact method published by the maintainer on GitHub. If no private contact method is available, open a public issue containing only a request for a private contact channel. Do not include vulnerability details, proof-of-concept material, secrets, or other sensitive information in that issue.

## What to include

A useful report should include, where applicable:

- affected release, commit, image, or branch;
- affected component;
- security impact and who or what is exposed;
- prerequisites or attack conditions;
- steps to reproduce;
- proof-of-concept information sufficient to validate the issue;
- known mitigations or workarounds;
- suggested remediation, if you have one.

Please remove unrelated credentials, private keys, tokens, personal data, network identifiers, and other sensitive information from logs or attachments.

## Scope

Security reports are appropriate for project-specific issues such as:

- unsafe behaviour introduced by this repository's build or image logic;
- privilege-boundary or command-execution flaws in project scripts;
- project-specific supply-chain or source-verification failures;
- secrets or sensitive material unintentionally included in a published project artifact;
- security defects in project-maintained kernel patches, device-tree changes, drivers, or integration;
- release or update behaviour that could cause users to trust unverified or substituted content.

General vulnerabilities in upstream Linux, Arch Linux ARM, firmware, or other third-party software should normally be reported to the relevant upstream project unless this repository introduces or materially changes the vulnerable behaviour.

Normal functional bugs belong in the public bug-report form.

## Supported versions

Security reports are welcome for the current stable release and the current `main` branch.

Reports affecting older releases are also useful, but this project does not promise security backports to every historical release. Development branches are not stable releases and may change before promotion.

## Coordinated disclosure

Please allow reasonable time for the report to be validated and, when necessary, for a fix and release to be prepared before public disclosure.

When appropriate, the maintainer may use a GitHub Security Advisory to coordinate remediation and publish the final disclosure. Reporter credit can be included if desired.

No fixed response-time SLA is currently promised.
