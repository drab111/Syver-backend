# Syver Backend
> Backend service built with **Vapor**, supporting the Syver iOS application and Safari Web Extension
> The client application is available here: https://github.com/drab111/Syver

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [API Endpoints](#api-endpoints)
4. [Caching & Refresh Policy](#caching--refresh-policy)
5. [Rate Limiting](#rate-limiting)
6. [Admin Endpoints](#admin-endpoints)
7. [Legacy Summaries Endpoints](#legacy-summaries-endpoints)
8. [Configuration](#configuration)
9. [Testing Strategy](#testing-strategy)
10. [Deployment](#deployment)
11. [Project Structure](#project-structure)
12. [License](#license)
13. [Contact](#contact)

---

## Overview

The Syver backend is a **Vapor service** that supports the iOS app and Safari extension by providing:

- Fetching and normalization of available AI models from OpenRouter
- Caching of model metadata to reduce upstream traffic
- A configuration endpoint for the minimum supported iOS app version
- Basic request rate limiting
- Admin-only endpoints for forced cache refresh

The backend does **not** store user data or AI summaries, and does not perform authentication or user management.  
All AI requests initiated by users are sent **directly from the client** to OpenRouter using the user’s own API key.

---

## Architecture

The backend is organized into clear layers:

- **Controllers** – HTTP routing and request validation
- **Services** – integration with external APIs
- **Policies** – pure decision logic
- **Middleware** – cross-cutting concerns such as rate limiting

---

## API Endpoints

### Configuration

#### `GET /config/ios-min-version`

Returns the minimum supported iOS app version configured on the server.  
Used by the iOS app to enforce server-driven update requirements.

### Models

#### `GET /models`

Returns cached AI model metadata fetched from OpenRouter.

- Default behavior: cache-only
- Optional query parameter: `?refresh=true`
  - Allows conditional revalidation based on the refresh policy
  - Does not guarantee an upstream fetch

---

#### `POST /models/refresh`

Forces a refresh of cached model metadata.

- Protected endpoint
- Requires the `X-Admin-Key` header
- Bypasses cache and refresh throttling
- Intended for operational use only

---

## Caching and Refresh Policy

Model metadata is cached in memory.

A dedicated refresh policy controls when cached data may be refreshed from the upstream API:

- Cached data is always preferred for public requests
- Revalidation is allowed only after a configured time interval
- Admin requests can force a refresh regardless of timing

The refresh decision logic is implemented as a pure, testable component.

---

## Rate Limiting

A global per-IP rate limiting middleware is applied.

- Limits request bursts across all public endpoints
- Implemented in memory
- Returns `429 Too Many Requests` when the limit is exceeded

The middleware is tested independently to verify correct behavior.

---

## Admin Endpoints

Administrative actions are protected using a static admin key.

- The admin key is provided via environment variables
- Requests must include the correct `X-Admin-Key` header
- No user-facing authentication is implemented

This mechanism matches the operational scope of the service.

---

## Legacy Summaries Endpoints

The backend still contains legacy summarization endpoints, but:

- They are disabled by default
- They are feature-flagged via environment variables
- They are no longer used by current clients

Summarization was moved entirely to the Safari extension to avoid unnecessary backend dependency and simplify deployment.

The legacy code remains for reference only.

---

## Configuration

The backend is configured using environment variables.

| Variable | Description |
|--------|-------------|
| `PORT` | HTTP server port |
| `IOS_MIN_VERSION` | Minimum supported iOS app version |
| `OPENROUTER_KEY` | Server-side OpenRouter API key |
| `ADMIN_REFRESH_KEY` | Admin key for protected endpoints |
| `ENABLE_SUMMARIES` | Enables legacy summaries endpoints |

---

## Testing Strategy

The project uses both integration and unit tests.

### Integration Tests

- Core application endpoints
- Error paths and authorization failures
- Executed against a fully configured application instance

### Unit Tests

- Refresh policy decision logic
- Rate limiting middleware behavior

---

## Deployment

The backend is deployed on Railway.

- Single-instance deployment
- In-memory cache is safe under this setup
- Docker-based multi-stage build

---

## Project Structure

```text
Sources/
└─ App/
   ├─ Controllers/
   ├─ DTOs/
   ├─ Middleware/
   ├─ Services/
   │  └─ Policies/
   ├─ configure.swift
   ├─ entrypoint.swift
   └─ routes.swift

Tests/
└─ AppTests/
   ├─ AppIntegrationTests.swift
   ├─ RateLimitMiddlewareTests.swift
   └─ RefreshPolicyTests.swift

Dockerfile
Package.swift
```

---

## License

This project is licensed under:

**Creative Commons Attribution‑NonCommercial‑NoDerivatives 4.0 International**

See `LICENSE` for details.

---

## Contact

If you have any questions about the project, feel free to reach out at:
**wiktor.drab@icloud.com**

---
