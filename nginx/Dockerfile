FROM nginx:alpine

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create certificates directory
RUN mkdir -p /etc/nginx/certs

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1/health || exit 1

# Expose ports
EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
