# Cloudflare CDN + S3 Setup Guide

This guide provides step-by-step instructions for setting up Stream Bucket with Cloudflare CDN and S3-compatible storage.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Recommended: Backblaze B2 with Cloudflare](#recommended-backblaze-b2-with-cloudflare)
3. [Alternative: Cloudflare R2](#alternative-cloudflare-r2)
4. [Alternative: AWS S3 with CloudFront](#alternative-aws-s3-with-cloudfront)
5. [Application Configuration](#application-configuration)
6. [Testing Your Setup](#testing-your-setup)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- A Cloudflare account with at least one domain
- An S3-compatible storage account (B2, R2, AWS S3, etc.)
- Stream Bucket application installed

---

## Recommended: Backblaze B2 with Cloudflare

This is the configuration we've tested and recommend for use with Cloudflare's free CDN.

### Step 1: Create B2 Bucket

1. Log into your [Backblaze B2 account](https://secure.backblaze.com/b2dashboard.htm)
2. Go to **Buckets** → **Create a Bucket**
3. Configure:
   - Bucket name: `streaming-content` (or your preferred name)
   - Bucket type: `Private` (recommended for CDN)
   - S3-compatible API: Enabled (default)
4. Click **Create Bucket**

### Step 2: Create Application Key

1. Go to **App Keys** → **Add Application Key**
2. Configure:
   - Key name: `Stream Bucket`
   - Bucket: Select your bucket
   - Permissions: Read and Write
3. Click **Create Key**
4. **Copy** the Key ID and Application Key (you won't see them again!)

### Step 3: Configure Cloudflare DNS

1. Go to **DNS** in Cloudflare dashboard
2. Add a CNAME record:
   ```
   Type: CNAME
   Name: stream (or your preferred subdomain)
   Target: s3.us-west-004.backblazeb2.com
   TTL: Auto
   Proxy status: Proxied (orange cloud)
   ```

   **Note:** Choose the region closest to your audience:
   - `s3.us-west-004.backblazeb2.com` (US West)
   - `s3.us-east-005.backblazeb2.com` (US East)
   - `s3.eu-central-001.backblazeb2.com` (EU)

### Step 4: Configure Bucket CORS

1. In B2 bucket settings, go to **CORS**
2. Add allowed origins:
   - `*` (for all) or your specific domain
   - Allowed methods: `GET, HEAD, OPTIONS, PUT`
   - Allowed headers: `*`

---

## Alternative: Cloudflare R2

Cloudflare R2 provides S3-compatible storage with no egress fees and direct Cloudflare integration.

### Step 1: Create R2 Bucket

1. Log into your [Cloudflare dashboard](https://dash.cloudflare.com/)
2. Navigate to **R2** in the left sidebar
3. Click **Create bucket**
4. Enter a bucket name (e.g., `streaming-content`)
5. Click **Create**

### Step 2: Create API Credentials

1. In the R2 dashboard, click **Manage R2 API tokens**
2. Click **Create API token**
3. Give it a name (e.g., `Stream Bucket Access`)
4. Set permissions:
   - **Account R2 Storage** → **Read and Write**
5. Click **Continue to summary**
6. Click **Create token**
7. **Copy** the Access Key ID and Secret Access Key (you won't see them again!)

### Step 3: Configure DNS

1. Go to **DNS** in Cloudflare dashboard
2. Add a CNAME record:
   ```
   Type: CNAME
   Name: stream (or your preferred subdomain)
   Target: your-bucket-name.r2.cloudflarestorage.com
   TTL: Auto
   Proxy status: Proxied (orange cloud)
   ```

   **Note:** The CNAME target format is `{bucket-name}.r2.cloudflarestorage.com`

### Step 4: Configure CORS (Optional, for browser playback)

1. In R2 bucket settings, go to **CORS**
2. Add allowed origins:
   - `*` (for all) or your specific domain
   - Allowed methods: `GET, HEAD, OPTIONS`
   - Allowed headers: `*`

---

## Option C: AWS S3 with CloudFront

### Step 1: Create S3 Bucket

1. Log into [AWS Console](https://console.aws.amazon.com/s3/)
2. Click **Create bucket**
3. Configure:
   - Bucket name: `streaming-content`
   - Region: Choose closest to your audience
   - Block public access: **Uncheck** all (required for CDN)
4. Click **Create bucket**

### Step 2: Create IAM User

1. Go to **IAM** → **Users** → **Add user**
2. Configure:
   - User name: `stream-bucket-user`
   - Access type: **Programmatic access**
3. Attach existing policies directly:
   - `AmazonS3FullAccess` (or create custom policy)
4. Click **Review** → **Create user**
5. **Copy** Access Key ID and Secret Access Key

### Step 3: Configure Bucket Policy

1. Go to S3 bucket → **Permissions** → **Bucket policy**
2. Add policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::streaming-content/*"
        }
    ]
}
```

### Step 4: Configure CORS

1. Go to S3 bucket → **Permissions** → **CORS configuration**
2. Add configuration:

```json
[
    {
        "AllowedHeaders": ["*"],
        "AllowedMethods": ["GET", "HEAD", "OPTIONS", "PUT"],
        "AllowedOrigins": ["*"],
        "ExposeHeaders": [],
        "MaxAgeSeconds": 3000
    }
]
```

### Step 5: Create CloudFront Distribution

1. Go to **CloudFront** → **Create Distribution**
2. Web distribution settings:
   - Origin domain: Select your S3 bucket
   - Origin access: **Origin access control (OAC)**
   - Default cache behavior:
     - Viewer protocol policy: Redirect HTTP to HTTPS
     - Allowed HTTP methods: GET, HEAD, OPTIONS
   - Distribution settings:
     - Price class: Choose appropriate
     - Alternate domain names (CNAME): `stream.yourdomain.com`
     - SSL certificate: ACM certificate for your domain
3. Click **Create Distribution**

---

## Application Configuration

### Adding S3 Profile in Stream Bucket

1. Open **Stream Bucket** application
2. Go to the **Upload** tab
3. Click the **+** button to add a new connection
4. Fill in the form:

#### For Cloudflare R2:
```
Name: Cloudflare R2
Endpoint: https://1234567890abcdef.r2.cloudflarestorage.com
Bucket: streaming-content
CDN URL: https://stream.yourdomain.com
Target Folder: (optional) e.g., videos/
CDN Path to Strip: (optional) e.g., /videos
```

#### For Backblaze B2:
```
Name: Backblaze B2
Endpoint: https://s3.us-west-004.backblazeb2.com
Bucket: streaming-content
CDN URL: https://stream.yourdomain.com
Target Folder: (optional) e.g., hls/
CDN Path to Strip: (optional) e.g., /hls
```

#### For AWS S3:
```
Name: AWS S3
Endpoint: https://s3.us-east-1.amazonaws.com
Bucket: streaming-content
CDN URL: https://d1234567890.cloudfront.net
Target Folder: (optional) e.g., streams/
CDN Path to Strip: (optional) e.g., /streams
```

5. Enter credentials:
   - Access Key ID
   - Secret Access Key

6. Click **Test Connection**

### Live Streaming Configuration

For live streaming with automatic S3 upload:

1. In the **Live** tab, set up your stream:
   - Stream title
   - Stream key (use a unique identifier)

2. In S3 Profile settings:
   - Set `Target Folder` to `live/`
   - Set `CDN Path to Strip` to `/live`

3. Start the server and connect your encoder to:
   ```
   rtmp://localhost:1935/live/your-stream-key
   ```

### VOD Processing Configuration

For batch processing:

1. Add video files to the queue in **Convert** tab
2. Select encoding presets
3. Enable **S3 Upload** in settings
4. Select your S3 profile
5. Start processing

---

## Testing Your Setup

### Test S3 Connection

1. In **Upload** tab, click **Test Connection**
2. Should show "Connection successful"

### Test File Upload

1. Add a small video file to the queue
2. Enable S3 upload
3. Start processing
4. Check S3 bucket for uploaded files

### Test CDN Playback

1. After upload, the app shows the CDN URL
2. Copy the URL and open in browser
3. Should play in HTML5 video player

### Test Live Streaming

1. Start server in **Live** tab
2. Connect OBS or other encoder
3. Verify HLS playlist at:
   ```
   https://stream.yourdomain.com/live/master.m3u8
   ```

---

## Troubleshooting

### Connection Issues

| Problem | Solution |
|---------|----------|
| "Connection failed" | Verify endpoint URL, access key, secret key |
| "Bucket not found" | Check bucket name spelling |
| "Access denied" | Verify IAM permissions and CORS settings |

### CDN Issues

| Problem | Solution |
|---------|----------|
| 403 Forbidden | Check bucket policy and CORS |
| 404 Not Found | Verify DNS CNAME and proxy status |
| Slow loading | Check CloudFront distribution status |

### Live Streaming Issues

| Problem | Solution |
|---------|----------|
| No video | Check encoder settings and stream key |
| Audio only | Verify audio codec settings |
| Buffering | Check segment length and bitrate |

### Common Endpoint URLs

| Provider | Endpoint Format |
|----------|-----------------|
| Cloudflare R2 | `https://{account-id}.r2.cloudflarestorage.com` |
| Backblaze B2 | `https://s3.{region}.backblazeb2.com` |
| AWS S3 | `https://s3.{region}.amazonaws.com` |

---

## Security Best Practices

1. **Use IAM roles** instead of root credentials
2. **Enable MFA** on your storage accounts
3. **Rotate keys** regularly
4. **Use least privilege** permissions
5. **Monitor access logs** for suspicious activity

---

## Advanced Configuration

### Custom Domain with SSL

1. Request SSL certificate in Cloudflare:
   - Go to **SSL/TLS** → **Certificates**
   - Use Cloudflare Origin CA or upload your own

2. Configure bucket for custom domain:
   - R2: Automatic with CNAME
   - B2: Use Cloudflare Workers or custom SSL
   - S3: Use CloudFront with custom SSL

### CDN Caching

Configure cache behavior in Cloudflare:
- **Caching** → **Configuration**
- Set TTL values for HLS segments
- Enable "Cache Level: Standard"
- Add page rules for specific paths

### Rate Limiting

Protect your origin:
- **Security** → **WAF** → **Tools**
- Create rate limiting rules
- Protect against abuse

---

## Support

For additional help:
- Cloudflare R2 Docs: https://developers.cloudflare.com/r2/
- Backblaze B2 Docs: https://www.backblaze.com/b2/docs/
- AWS S3 Docs: https://docs.aws.amazon.com/AmazonS3/
- Stream Bucket: Check application logs in `hls-live-log.txt`

---

## Licence

[![PolyForm Strict 1.0.0](https://img.shields.io/badge/license-PolyForm%20Strict%201.0.0-blue)](https://polyformproject.org/licenses/strict/1.0.0)

Stream Bucket is source-available under the PolyForm Strict License 1.0.0.
Free for personal and non-profit use. Commercial use requires a separate licence.

- Full licence: [LICENSE](LICENSE)
- Contribution guidelines: [CONTRIBUTING.md](CONTRIBUTING.md)
- Commercial enquiries: **[hello@reubendavern.com]**