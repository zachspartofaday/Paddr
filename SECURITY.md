# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a vulnerability, leaked credential, signing-material exposure, or a report containing sensitive controller or filesystem data. Use [GitHub's private vulnerability reporting form](https://github.com/zachspartofaday/Paddr/security/advisories/new) instead.

Include a concise impact description, reproduction steps, affected versions, and any suggested mitigation. Redact controller serial numbers, IOHID paths, local account names, certificates, private keys, and tokens.

Paddr reads HID input and can emit keyboard and mouse events after the user grants macOS permissions. Reports involving permission bypass, unexpected output, unsafe archive verification, or failure to release held output on disconnect are treated as security-relevant.

## Supported versions

Paddr is currently an early beta. Security fixes are applied to the latest published version; older beta builds may not receive separate patches.
