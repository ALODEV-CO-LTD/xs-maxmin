import type { NextConfig } from 'next'

// The site is a static client app served by nginx next to /api (same origin), exactly like the Vue build was:
// `next build` writes the whole site to ./out. In development /api (and the chat/call WebSocket) goes to the backend.
const nextConfig: NextConfig = {
  output: 'export',
  trailingSlash: false,
  images: { unoptimized: true },
  ...(process.env.NODE_ENV === 'development'
    ? { rewrites: async () => [{ source: '/api/:path*', destination: `${process.env.API_PROXY || 'http://localhost:8080'}/api/:path*` }] }
    : {}),
}

export default nextConfig
