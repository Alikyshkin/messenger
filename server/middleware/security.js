import helmet from 'helmet';
import config from '../config/index.js';

/**
 * Security headers middleware
 * Защищает от XSS, clickjacking, MIME sniffing и других атак
 */
export function securityHeaders() {
  return helmet({
    // Content Security Policy
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"], // Для Swagger UI
        scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'", "https://www.gstatic.com"], // Для Flutter CanvasKit и Swagger UI
        imgSrc: ["'self'", "data:", "https:"],
        connectSrc: ["'self'", "https://www.gstatic.com", "https://fonts.gstatic.com"], // Для Flutter CanvasKit и Google Fonts
        fontSrc: ["'self'", "data:", "https://fonts.gstatic.com"], // Для Google Fonts
        objectSrc: ["'none'"],
        mediaSrc: ["'self'"],
        frameSrc: ["'none'"],
      },
    },
    
    // XSS Protection
    xssFilter: true,
    
    // Prevent MIME type sniffing
    noSniff: true,
    
    // Prevent clickjacking
    frameguard: {
      action: 'deny',
    },
    
    // Hide X-Powered-By header
    hidePoweredBy: true,
    
    // HSTS (HTTP Strict Transport Security)
    hsts: {
      maxAge: 31536000, // 1 год
      includeSubDomains: true,
      preload: true,
    },
    
    // Referrer Policy
    referrerPolicy: {
      policy: 'strict-origin-when-cross-origin',
    },
    
    // Permissions Policy (Feature Policy)
    // camera и microphone разрешены для звонков (self = страница мессенджера)
    permissionsPolicy: {
      features: {
        camera: ["'self'"],
        microphone: ["'self'"],
        geolocation: ["'none'"],
      },
    },
    
    // Cross-Origin Embedder Policy
    crossOriginEmbedderPolicy: false, // Отключаем для совместимости с WebSocket
    
    // Cross-Origin Opener Policy
    crossOriginOpenerPolicy: {
      policy: 'same-origin',
    },
    
    // Cross-Origin Resource Policy
    crossOriginResourcePolicy: {
      policy: 'cross-origin',
    },
    
    // Отключаем некоторые заголовки в development для удобства разработки
    ...(config.nodeEnv === 'development' && {
      contentSecurityPolicy: false, // Отключаем CSP в dev для Swagger
    }),
  });
}
