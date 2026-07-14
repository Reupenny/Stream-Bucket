# Contributing to Stream Bucket

Thank you for your interest in Stream Bucket!

> ⚠️ **Licence notice:** This project is source-available under the
> [PolyForm Strict License 1.0.0](LICENSE). It is **not** open source in the
> OSI sense. Standard open-source contribution workflows (fork → modify →
> redistribute) are **not** permitted under the licence. Please read this
> document carefully before contributing.

---

## Table of Contents

- [How You Can Help](#how-you-can-help)
- [Bug Reports](#bug-reports)
- [Feature Requests](#feature-requests)
- [Security Disclosures](#security-disclosures)
- [Development Setup](#development-setup)
- [Building the Project](#building-the-project)
- [Coding Standards](#coding-standards)
- [Licence & CLA](#licence--cla)

---

## How You Can Help

Because of the PolyForm Strict licence, you **cannot** fork the repo and submit
a traditional pull request. However, your input is still genuinely valued:

| ✅ Permitted | ❌ Not permitted |
|---|---|
| File bug reports | Fork and redistribute the code |
| Suggest features via issues | Share modified versions with others |
| Report security issues privately | Use the project commercially without a licence |
| Read and study the source | Create competing derivative works |
| Propose code changes in an issue | Submit PRs containing your own copyrighted implementation |

---

## Bug Reports

When reporting a bug, please include:

1. **Description** — what happened vs. what you expected
2. **Steps to reproduce** — as minimal as possible
3. **Environment:**
   - macOS version
   - FFmpeg version (`ffmpeg -version`)
   - App version
4. **Logs** — export from the Live tab or attach `hls-live-log.txt`

---

## Feature Requests

Feature suggestions are welcome. Please open an issue with:

1. **What** — describe the feature clearly
2. **Why** — what problem does it solve for you?
3. **How** — any thoughts on how it could work (optional)


---

## Security Disclosures

Please **do not** open a public issue for security vulnerabilities.

Report privately by emailing: **[hello@reubendavern.com]**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested mitigations

You will receive a response within a couple of days. Public disclosure will be
coordinated after a fix is in place.

---

## Development Setup

If you are the project author or a licensed contributor:

### Prerequisites

- macOS 13.0 or later
- Swift 5.9 or later (via Xcode Command Line Tools)
- FFmpeg via Homebrew

```bash
# Install Homebrew if needed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install FFmpeg
brew install ffmpeg

# Verify
ffmpeg -version
```

---

## Building the Project

```bash
chmod +x build.sh #version number e.g. 1.0.0
./build.sh
```

This compiles all Swift sources and produces `Stream Bucket.app`.

### Manual build

```bash
swiftc -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -O \
    Sources/*.swift \
    -o Stream Bucket.app/Contents/MacOS/Stream Bucket
```

---

## Coding Standards

If you are a licensed contributor preparing changes:

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- `camelCase` for variables and functions; `PascalCase` for types
- 4-space indentation, no tabs
- Document public APIs with `///` doc comments
- Update `CHANGELOG.md` for any user-facing change

```swift
/// Processes a video file and generates HLS output.
/// - Parameters:
///   - input: The input video file URL
///   - outputDir: The output directory for HLS segments
/// - Returns: The URL to the master playlist
/// - Throws: Processing errors
func processVideo(input: URL, outputDir: URL) throws -> URL {
    // Implementation
}
```

---

## Licence & CLA

By submitting an issue, suggestion, or any other contribution to this
repository you agree that:

1. You are not conveying any copyrighted work or proprietary information.
2. Any ideas, feedback, or proposals you share may be incorporated into the
   project by the author under the project's existing licence terms, without
   any obligation to you.
3. You have read and understood the [PolyForm Strict License 1.0.0](LICENSE)
   and acknowledge that it governs use of this software.

For commercial licensing enquiries: **[hello@reubendavern.com]**