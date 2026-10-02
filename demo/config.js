// Terraform replaces this file for AWS. Cloudflare Workers uses its own /api routes.
window.CLOUDORDER_API_URL = location.hostname.endsWith(".workers.dev") ? "/api" : "";
