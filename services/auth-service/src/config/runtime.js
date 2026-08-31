import dotenv from 'dotenv';
import fs from 'fs';

dotenv.config();

const allowedEnvironments = ['development', 'staging', 'production', 'test'];
const appEnv = process.env.APP_ENV || process.env.NODE_ENV || 'development';

if (!allowedEnvironments.includes(appEnv)) {
  throw new Error(`APP_ENV invalide: ${appEnv}. Valeurs attendues: ${allowedEnvironments.join(', ')}`);
}

const resolveSecret = (envVal, defaultPath = '/run/secrets/jwt_secret') => {
  if (process.env.JWT_SECRET_FILE && fs.existsSync(process.env.JWT_SECRET_FILE)) {
    return fs.readFileSync(process.env.JWT_SECRET_FILE, 'utf8').trim();
  }
  if (fs.existsSync(defaultPath)) {
    return fs.readFileSync(defaultPath, 'utf8').trim();
  }
  if (envVal && fs.existsSync(envVal)) {
    return fs.readFileSync(envVal, 'utf8').trim();
  }
  return envVal;
};

const rawJwtSecret = resolveSecret(process.env.JWT_SECRET);
const isManagedEnvironment = ['staging', 'production'].includes(appEnv);
const jwtSecret = rawJwtSecret || (isManagedEnvironment ? undefined : 'dev_jwt_secret_change_me');

if (!jwtSecret) {
  throw new Error('JWT_SECRET est obligatoire en staging et en production.');
}

export const runtimeConfig = {
  serviceName: 'auth-service',
  appEnv,
  nodeEnv: process.env.NODE_ENV || appEnv,
  isTest: appEnv === 'test' || process.env.NODE_ENV === 'test',
  port: Number(process.env.PORT || 3001),
  corsOrigin: process.env.CORS_ORIGIN || 'http://localhost:8080',
  mongodbUri: process.env.MONGODB_URI || 'mongodb://mongodb:27017/auth',
  jwtSecret,
};
