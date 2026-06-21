# macOS Software Update and Application Compliance Checker

A macOS toolkit for checking update and application compliance and maintaining the built-in update services.

## Audit

```bash
chmod +x src/macos_software_compliance.sh
sudo ./src/macos_software_compliance.sh
```

Optional application assessment:

```bash
sudo ./src/macos_software_compliance.sh --app /Applications/Example.app
```

## Maintenance and repair

Preview service maintenance:

```bash
chmod +x src/macos_software_compliance_repair.sh
sudo ./src/macos_software_compliance_repair.sh --repair --dry-run
```

Run service maintenance:

```bash
sudo ./src/macos_software_compliance_repair.sh --repair
```

The repair script restarts the update and installer services, supports the built-in recommended or complete update modes, records every action, and runs a fresh update check afterward. Confirmation prompts and dry-run mode are included.

Update operations can take time and may require a restart. Application signature findings are reported but are not changed automatically.

## Author

Dewald Pretorius — L2 IT Support Engineer
