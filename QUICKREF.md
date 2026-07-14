# Quick Reference

## Common Commands

### Build
```bash
./build.sh
```

### Install FFmpeg
```bash
brew install ffmpeg
```

### Verify FFmpeg
```bash
ffmpeg -version
ffprobe -version
```

## S3 Endpoint URLs

| Provider | Endpoint |
|----------|----------|
| Cloudflare R2 | `https://{account-id}.r2.cloudflarestorage.com` |
| Backblaze B2 US West | `https://s3.us-west-004.backblazeb2.com` |
| Backblaze B2 US East | `https://s3.us-east-005.backblazeb2.com` |
| Backblaze B2 EU | `https://s3.eu-central-001.backblazeb2.com` |
| AWS S3 (us-east-1) | `https://s3.us-east-1.amazonaws.com` |
| AWS S3 (us-west-2) | `https://s3.us-west-2.amazonaws.com` |

## FFmpeg Presets

### VOD Optimized
- 1080p: 5000 kbps
- 720p: 2800 kbps
- 480p: 1400 kbps
- 240p: 400 kbps

### Streaming Lite
- 720p: 2800 kbps
- 480p: 1400 kbps
- 240p: 400 kbps

## File Structure

```
Sources/
├── AppMain.swift           # Entry point
├── AppTabView.swift        # Tab navigation
├── BatchProcessor.swift    # VOD processing
├── BucketBrowserView.swift # S3 browser
├── ContentView.swift       # Main UI
├── FFmpegWrapper.swift     # FFmpeg wrapper
├── KeychainHelper.swift    # Keychain storage
├── LiveServerProcess.swift # Live server
├── LiveStreamView.swift    # Live UI
├── ProcessorState.swift    # State management
├── QueuedFile.swift        # File model
├── S3Client.swift          # S3 API
├── S3Uploader.swift        # Upload logic
└── SpriteSheetGenerator.swift # Thumbnails
```

## Key Classes

| Class | Purpose |
|-------|---------|
| `BatchProcessor` | VOD file processing |
| `S3Client` | S3 API communication |
| `S3Uploader` | File upload to S3 |
| `FFmpegWrapper` | FFmpeg process execution |
| `LiveServerProcess` | Live streaming server |
| `ProcessorState` | App state management |
| `KeychainHelper` | Secure credential storage |

## S3 Profile Fields

| Field | Description |
|-------|-------------|
| `name` | Connection name |
| `endpoint` | S3 API endpoint |
| `bucket` | Bucket name |
| `cdnUrl` | CDN domain |
| `targetFolder` | Upload subfolder |
| `cdnPathToStrip` | Path prefix to remove |

## Live Streaming URL Format

```
RTMP Ingest: rtmp://localhost:1935/live/{stream-key}
HLS Output:  https://cdn.example.com/live/master.m3u8
```

## Debug Log Location

```
/Users/rdavern/ActiveProjects/HLSs/hls-live-log.txt
```

## Common Issues

| Issue | Solution |
|-------|----------|
| FFmpeg not found | `brew install ffmpeg` |
| S3 connection fails | Check endpoint, keys, bucket |
| CDN shows 403 | Check CORS and bucket policy |
| Live stream not appearing | Check encoder settings |

## API Endpoints

### S3 Operations
- `PUT` - Upload file
- `GET` - Download file
- `HEAD` - Check bucket/file
- `LIST` - List objects

### Authentication
- AWS Signature V4
- Access Key ID
- Secret Access Key

## CDN Configuration

### Cloudflare R2
- CNAME: `stream.yourdomain.com` → `bucket.r2.cloudflarestorage.com`
- Proxy: Proxied (orange cloud)

### Backblaze B2
- CNAME: `stream.yourdomain.com` → `s3.us-west-004.backblazeb2.com`
- Proxy: Proxied (orange cloud)

### AWS S3 + CloudFront
- CloudFront distribution → S3 bucket
- CNAME: `stream.yourdomain.com` → CloudFront domain

## Licence

[![PolyForm Strict 1.0.0](https://img.shields.io/badge/license-PolyForm%20Strict%201.0.0-blue)](https://polyformproject.org/licenses/strict/1.0.0)

Source-available, personal use only. Commercial use requires a licence.  
See [LICENSE](LICENSE) and [CONTRIBUTING.md](CONTRIBUTING.md) for details.