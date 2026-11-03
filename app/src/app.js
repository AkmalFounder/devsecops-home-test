'use strict';

const express = require('express');
const helmet = require('helmet');

const app = express();
const PORT = process.env.PORT || 8080;

// Security Middleware: Set security HTTP headers (XSS, HSTS, no-sniff, etc.)
app.use(helmet());
app.use(express.json({ limit: '10kb' })); // Mitigate Large Payload Denial-of-Service

// Environment & Secret Configuration (Retrieved at runtime from ECS/Secrets Manager)
const APP_ENV = process.env.APP_ENV || 'production';
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_NAME = process.env.DB_NAME || 'appdb';

// Liveness & Readiness Probes for ALB / Container Health Checks
app.get('/healthz', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.get('/ready', (req, res) => {
  // Check if critical environment variables are injected at runtime
  const hasDbConfig = Boolean(process.env.DB_PASSWORD);
  if (!hasDbConfig && APP_ENV === 'production') {
    return res.status(503).json({
      status: 'unready',
      message: 'Database secrets not yet provisioned'
    });
  }
  return res.status(200).json({ status: 'ready' });
});

// Sample API Endpoint
app.get('/api/v1/info', (req, res) => {
  res.status(200).json({
    service: 'backend-api',
    version: '1.0.0',
    environment: APP_ENV,
    securityControls: [
      'Least Privilege IAM Execution Roles',
      'Secrets Injected via AWS Secrets Manager at Task Boot',
      'Container runs as Non-Root User',
      'Multi-stage Docker build without build-tools in production'
    ]
  });
});

// Centralized Error Handler (Prevent Information Disclosure & Stack Trace Leaks)
app.use((err, req, res, next) => {
  console.error(`[ERROR] Unhandled exception: ${err.message}`);
  res.status(500).json({
    error: 'Internal Server Error',
    message: APP_ENV === 'production' ? 'An unexpected error occurred' : err.message
  });
});

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`[INFO] Application started on port ${PORT} in ${APP_ENV} mode.`);
});

// Graceful Shutdown for ECS Task Termination / SIGTERM
process.on('SIGTERM', () => {
  console.log('[INFO] SIGTERM signal received. Closing HTTP server gracefully...');
  server.close(() => {
    console.log('[INFO] HTTP server closed. Exiting process.');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('[INFO] SIGINT received. Shutting down...');
  server.close(() => process.exit(0));
});

module.exports = app;
