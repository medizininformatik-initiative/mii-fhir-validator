FROM nginx:alpine@sha256:7fc0fb4af7bf006aeb31aea88069976060f8f0a0a86b667126742cc17f4e31ae

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create certificates directory
RUN mkdir -p /etc/nginx/certs

# Health check; shell form for `|| exit 1` (Docker reserves exit code 2)
# hadolint ignore=DL3025
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1/health || exit 1

# Expose ports
EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
