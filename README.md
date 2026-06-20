# macOS Software Update and Application Compliance Checker

A read-only Bash toolkit for reporting pending macOS updates, installed applications, versions, code signatures, notarisation results, and basic compliance findings.

## Usage

```bash
chmod +x src/macos_software_compliance.sh
sudo ./src/macos_software_compliance.sh
```

Optional application assessment:

```bash
sudo ./src/macos_software_compliance.sh --app /Applications/Example.app
```

## Checks performed

- macOS version and build
- Pending updates and installation history
- Installed applications and versions
- Code-signature and Gatekeeper assessment for an optional app
- Applications missing version metadata or signatures
- Text, CSV, and JSON reports

## Safety

The script never installs updates, removes applications, changes trust settings, or modifies quarantine attributes.

## Author

Dewald Pretorius — L2 IT Support Engineer
