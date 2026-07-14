# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive README.md with project overview and usage instructions
- Detailed SETUP.md with Cloudflare CDN + S3 configuration guides
- Support for multiple S3-compatible storage providers (R2, B2, AWS S3)
- Live streaming with automatic HLS output
- VOD batch processing with multiple bitrate renditions
- Secure credential storage via macOS Keychain
- Thumbnail generation and sprite sheet creation
- VTT subtitle generation

## [1.0.0] - Initial Release

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

| Version | Date | Description |
|---------|------|-------------|
| 1.0.0 | 2024 | Initial release |
| Unreleased | Current | Documentation and setup guides |

---

## Roadmap

### Planned Features
- [ ] Web-based management interface
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

None in version 1.0.0

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