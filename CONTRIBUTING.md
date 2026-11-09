# Contributing

Changes are welcome through issues and pull requests.

- Keep the original exploit author credits and GPL notices intact.
- Describe the behavior changed and the checks you performed.
- Keep UI work in the browser/presentation code when possible. Document changes to the upstream exploit or enumeration implementation explicitly.
- Treat a returned extension handle and a successful directory read as separate results.
- Use sample-data mode for public screenshots.
- Do not include signing assets, passwords, team/device identifiers, private bundle/App Group identifiers, device logs, personal container paths, or signed app artifacts in a contribution.
- Run `Tools/BuildUnsigned.sh` for a signing-independent compile check. Physical-device exploit testing requires your own valid signing setup.

Contributions are distributed under GPL-3.0-or-later as part of this project.
