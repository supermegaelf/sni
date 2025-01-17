#!/bin/bash

# Function to prompt for user input
get_user_input() {
    read -p "SNI domain: " DOMAIN
    read -p "Email address for certbot: " EMAIL
    read -p "CF email: " CF_EMAIL
    read -p "CF API key: " CF_API_KEY
}

# Get user input
get_user_input

# Install required packages
apt install snapd -y
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
snap set certbot trust-plugin-with-root=ok
snap install certbot-dns-cloudflare

# Create and secure the secrets directory
mkdir -p /root/.secrets/
cat > /root/.secrets/cloudflare.ini << EOF
dns_cloudflare_email = "${CF_EMAIL}"
dns_cloudflare_api_key = "${CF_API_KEY}"
EOF
chmod 700 /root/.secrets/
chmod 400 /root/.secrets/cloudflare.ini

# Get SSL certificate
certbot certonly --dns-cloudflare \
    --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 30 \
    -d "${DOMAIN}" \
    -d "*.${DOMAIN}" \
    --email "${EMAIL}" \
    --agree-tos \
    --non-interactive

# Create SSL configuration
cat > /etc/nginx/snippets/ssl.conf << EOF
ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
ssl_dhparam /etc/ssl/certs/dhparam.pem;
EOF

# Create Nginx site configuration
cat > /etc/nginx/conf.d/sni-site.conf << EOF
server {
    server_name  ${DOMAIN};

    listen 8444 ssl proxy_protocol;
    http2 on;

    gzip on;

    location / {
        root /usr/share/nginx/html;
        index sni.html;
    }

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/ssl-params.conf;
}
EOF

# Download SNI page
wget -q https://raw.githubusercontent.com/supermegaelf/sni-page/main/sni.html -O /usr/share/nginx/html/sni.html

# Update Nginx main configuration
cat > /etc/nginx/nginx.conf << 'EOF'
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    gzip on;
    gzip_disable "msie6";

    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_types
      application/atom+xml
      application/geo+json
      application/javascript
      application/x-javascript
      application/json
      application/ld+json
      application/manifest+json
      application/rdf+xml
      application/rss+xml
      application/xhtml+xml
      application/xml
      font/eot
      font/otf
      font/ttf
      image/svg+xml
      text/css
      text/javascript
      text/plain
      text/xml;

    resolver 8.8.8.8 8.8.4.4;

    include /etc/nginx/conf.d/*.conf;
}
EOF

# Test and restart Nginx
nginx -t && systemctl restart nginx
