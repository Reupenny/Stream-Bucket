# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-02

### Added

- Screenshot gallery in README covering the Convert, Upload, and Live tabs
- "Installing & Running" section documenting the right-click → Open workaround for
  Gatekeeper on the unsigned, unnotarized build
- `DesignKit` helpers for spring-based, interruptible motion that honours the
  system Reduce Motion accessibility setting
- `PressableButtonStyle` / `PressablePlainStyle` for instant press-down feedback
  on buttons across the app
- S3 `downloadObject` support for fetching bucket objects to a local file
- Comprehensive README.md with project overview and usage instructions
- Detailed SETUP.md with Cloudflare CDN + S3 configuration guides
- Support for multiple S3-compatible storage providers (R2, B2, AWS S3)
- Live streaming with automatic HLS output
- VOD batch processing with multiple bitrate renditions
- Secure credential storage via macOS Keychain
- Thumbnail generation and sprite sheet creation

### Changed

- S3 Cloud File Explorer: added download and refresh affordances
- Live view and bucket browser UI polish
- Clarified README wording and restructured the S3 profile configuration section

## [0.1.0] - Initial Release

### Added

- Stream Bucket macOS application
- VOD processing with FFmpeg
- S3 upload functionality
- Live streaming server
- Multi-resolution encoding (1080p, 720p, 480p, 240p)
- S3 profile management
- Bucket browser for file management
- Application state persistence
- Build script for macOS app bundle creation

---

## Version History

| Version    | Date       | Description                                          |
| ---------- | ---------- | ---------------------------------------------------- |
| 0.2.0      | 2026-10-02 | Screenshots, motion/press-feel UI pass, S3 downloads |
| 0.1.0      | 2026       | Initial release                                      |
| Unreleased | Current    | Documentation and setup guides                       |

---

## Roadmap

### Planned Features

- [ ] Scheduled streaming automation
- [ ] Recording archive management
- [ ] Analytics dashboard
- [ ] Multi-stream support
- [ ] Custom FFmpeg presets
- [ ] Webhook notifications
- [ ] Docker deployment option

---

## Migration Guide

### Upgrading from Previous Versions

When upgrading from a previous version:

1. **Backup your profiles**: Export S3 profiles from the Upload tab
2. **Update FFmpeg**: Ensure you have the latest version
3. **Re-import profiles**: Add your S3 connections again
4. **Test connections**: Verify all connections work

### Breaking Changes

None in version 0.2.0

> **Note on versioning:** Stream Bucket was previously built and shared under
> inconsistent `1.0.x` labels that were never published as real releases. `0.1.0`
> is the first public release, and the version line has been reset to `0.x`.

---

## Contributing

We welcome contributions! Please see our contributing guidelines for more information.

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Security

If you discover any security-related issues, please email security@example.com instead of using a GitHub issue.

---

## License

This project is licensed under the MIT License - see the LICENSE file for details.
