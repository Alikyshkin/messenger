import swaggerJsdoc from 'swagger-jsdoc';
import { DEFAULT_HTTP_PORT } from '../config/constants.js';

const options = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'Messenger API',
      version: '1.0.0',
      description: 'API документация для мессенджера',
      contact: {
        name: 'API Support',
      },
    },
    servers: [
      {
        url: `http://localhost:${DEFAULT_HTTP_PORT}`,
        description: 'Development server',
      },
      {
        url: 'https://api.example.com',
        description: 'Production server',
      },
    ],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
        },
      },
      schemas: {
        User: {
          type: 'object',
          properties: {
            id: { type: 'integer' },
            username: { type: 'string' },
            display_name: { type: 'string' },
            bio: { type: 'string', nullable: true },
            avatar_url: { type: 'string', nullable: true },
            created_at: { type: 'string', format: 'date-time' },
            public_key: { type: 'string', nullable: true },
            is_online: { type: 'boolean' },
            last_seen: { type: 'string', format: 'date-time', nullable: true },
          },
        },
        Message: {
          type: 'object',
          properties: {
            id: { type: 'integer' },
            sender_id: { type: 'integer' },
            receiver_id: { type: 'integer' },
            content: { type: 'string' },
            created_at: { type: 'string', format: 'date-time' },
            read_at: { type: 'string', format: 'date-time', nullable: true },
            attachment_url: { type: 'string', nullable: true },
            attachment_filename: { type: 'string', nullable: true },
            message_type: { type: 'string', enum: ['text', 'poll'] },
            is_mine: { type: 'boolean' },
          },
        },
        Group: {
          type: 'object',
          properties: {
            id: { type: 'integer' },
            name: { type: 'string' },
            avatar_url: { type: 'string', nullable: true },
            created_by_user_id: { type: 'integer' },
            created_at: { type: 'string', format: 'date-time' },
            my_role: { type: 'string', enum: ['admin', 'member'] },
            member_count: { type: 'integer' },
          },
        },
        Error: {
          type: 'object',
          properties: {
            error: { type: 'string' },
          },
        },
      },
    },
    security: [
      {
        bearerAuth: [],
      },
    ],
  },
  apis: ['./routes/*.js'], // Путь к файлам с аннотациями
};

export const swaggerSpec = swaggerJsdoc(options);
