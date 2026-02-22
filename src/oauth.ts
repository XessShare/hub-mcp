/*
   Copyright 2025 Docker Hub MCP Server authors

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

/**
 * OAuth 2.1 Authorization Server implementation for the Docker Hub MCP Server.
 *
 * Implements:
 *   - RFC 8414  – OAuth 2.0 Authorization Server Metadata (/.well-known/oauth-authorization-server)
 *   - RFC 7591  – OAuth 2.0 Dynamic Client Registration (/register)
 *   - OAuth 2.1 Authorization Code + PKCE flow (/authorize  GET/POST, /token)
 *
 * The authorization step verifies the caller's Docker Hub username and Personal Access
 * Token (PAT).  On success the server issues an opaque MCP access token that carries
 * the Docker Hub JWT so downstream API calls can be made on the user's behalf.
 */

import { Router, Request, Response, NextFunction } from 'express';
import * as crypto from 'crypto';
import { logger } from './logger';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ClientRegistration {
    client_id: string;
    client_name: string;
    redirect_uris: string[];
    grant_types: string[];
    response_types: string[];
    token_endpoint_auth_method: string;
}

interface AuthCodeData {
    client_id: string;
    redirect_uri: string;
    code_challenge: string;
    code_challenge_method: string;
    scope: string;
    state?: string;
    username: string;
    hub_token: string;
    expires_at: number; // ms since epoch
}

export interface OAuthTokenData {
    client_id: string;
    scope: string;
    username: string;
    hub_token: string; // Docker Hub JWT – used as Bearer token for Hub API calls
    expires_at: number; // ms since epoch
}

// ---------------------------------------------------------------------------
// In-memory stores  (single-process; sufficient for the stateless HTTP model)
// ---------------------------------------------------------------------------

const registeredClients = new Map<string, ClientRegistration>();
const authCodes = new Map<string, AuthCodeData>();
const accessTokens = new Map<string, OAuthTokenData>();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function generateToken(bytes = 32): string {
    return crypto.randomBytes(bytes).toString('base64url');
}

/**
 * Verify a PKCE code_verifier against the stored code_challenge.
 * Only S256 is supported (S256 is REQUIRED by OAuth 2.1).
 */
function verifyPKCE(verifier: string, challenge: string, method: string): boolean {
    if (method !== 'S256') return false;
    const hash = crypto.createHash('sha256').update(verifier).digest('base64url');
    try {
        return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(challenge));
    } catch {
        return false;
    }
}

/**
 * Exchange Docker Hub username + PAT for a short-lived Hub JWT.
 * Returns null on failure (invalid credentials or network error).
 */
async function dockerHubLogin(username: string, password: string): Promise<string | null> {
    try {
        const res = await fetch('https://hub.docker.com/v2/users/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password }),
        });
        if (!res.ok) return null;
        const data = (await res.json()) as { token?: string };
        return data.token ?? null;
    } catch (err) {
        logger.error(`dockerHubLogin: network error – ${err}`);
        return null;
    }
}

// ---------------------------------------------------------------------------
// Authorization HTML form
// ---------------------------------------------------------------------------

function escapeHtml(str: string): string {
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function buildAuthorizeHtml(params: {
    client_id: string;
    redirect_uri: string;
    code_challenge: string;
    code_challenge_method: string;
    scope: string;
    state: string;
    error?: string;
}): string {
    const errorHtml = params.error
        ? `<p class="error">${escapeHtml(params.error)}</p>`
        : '';

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Authorize – Docker Hub MCP Server</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, -apple-system, sans-serif;
      background: #f0f4f8;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .card {
      background: #fff;
      border-radius: 8px;
      box-shadow: 0 2px 16px rgba(0,0,0,.12);
      padding: 36px 32px;
      width: 100%;
      max-width: 400px;
    }
    h1 { font-size: 20px; margin-bottom: 6px; }
    .subtitle { color: #555; font-size: 14px; margin-bottom: 24px; }
    .error { color: #c62828; font-size: 13px; margin-bottom: 12px; }
    label { display: block; font-size: 13px; font-weight: 600; color: #333; margin-bottom: 4px; }
    input[type=text], input[type=password] {
      width: 100%; padding: 8px 12px;
      border: 1px solid #ccc; border-radius: 4px;
      font-size: 14px; margin-bottom: 16px;
    }
    input:focus { outline: none; border-color: #0066ff; box-shadow: 0 0 0 2px rgba(0,102,255,.15); }
    button {
      width: 100%; padding: 10px;
      background: #0066ff; color: #fff;
      border: none; border-radius: 4px;
      font-size: 14px; font-weight: 600;
      cursor: pointer;
    }
    button:hover { background: #0052cc; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Docker Hub MCP Server</h1>
    <p class="subtitle">Sign in with your Docker Hub credentials to authorize access.</p>
    ${errorHtml}
    <form method="POST" action="/authorize">
      <input type="hidden" name="client_id"             value="${escapeHtml(params.client_id)}">
      <input type="hidden" name="redirect_uri"          value="${escapeHtml(params.redirect_uri)}">
      <input type="hidden" name="code_challenge"        value="${escapeHtml(params.code_challenge)}">
      <input type="hidden" name="code_challenge_method" value="${escapeHtml(params.code_challenge_method)}">
      <input type="hidden" name="scope"                 value="${escapeHtml(params.scope)}">
      <input type="hidden" name="state"                 value="${escapeHtml(params.state)}">
      <label for="username">Docker Hub Username</label>
      <input type="text"     id="username" name="username" required
             autocomplete="username" placeholder="e.g. myuser">
      <label for="pat">Personal Access Token</label>
      <input type="password" id="pat"      name="pat"      required
             autocomplete="current-password" placeholder="dckr_pat_…">
      <button type="submit">Authorize</button>
    </form>
  </div>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Router factory
// ---------------------------------------------------------------------------

/**
 * Creates an Express Router that provides the full OAuth 2.1 + PKCE server.
 *
 * @param issuerBaseUrl  The base URL of the MCP server (e.g. "http://localhost:3000").
 *                       Used to construct endpoint URLs in the metadata document.
 */
export function createOAuthRouter(issuerBaseUrl: string): Router {
    const router = Router();

    // -----------------------------------------------------------------------
    // RFC 8414 – Authorization Server Metadata
    // -----------------------------------------------------------------------
    router.get('/.well-known/oauth-authorization-server', (_req: Request, res: Response) => {
        res.json({
            issuer: issuerBaseUrl,
            authorization_endpoint: `${issuerBaseUrl}/authorize`,
            token_endpoint: `${issuerBaseUrl}/token`,
            registration_endpoint: `${issuerBaseUrl}/register`,
            response_types_supported: ['code'],
            grant_types_supported: ['authorization_code'],
            code_challenge_methods_supported: ['S256'],
            token_endpoint_auth_methods_supported: ['none'],
        });
    });

    // -----------------------------------------------------------------------
    // RFC 7591 – Dynamic Client Registration
    // -----------------------------------------------------------------------
    router.post('/register', (req: Request, res: Response): void => {
        const { client_name, redirect_uris, grant_types, response_types } = req.body as {
            client_name?: string;
            redirect_uris?: string[];
            grant_types?: string[];
            response_types?: string[];
        };

        if (!Array.isArray(redirect_uris) || redirect_uris.length === 0) {
            res.status(400).json({
                error: 'invalid_client_metadata',
                error_description: 'redirect_uris is required and must be a non-empty array',
            });
            return;
        }

        for (const uri of redirect_uris) {
            try {
                const u = new URL(uri);
                const isLocalhost = u.hostname === 'localhost' || u.hostname === '127.0.0.1';
                if (u.protocol !== 'https:' && !isLocalhost) {
                    res.status(400).json({
                        error: 'invalid_redirect_uri',
                        error_description: `redirect_uri must use HTTPS or be a localhost URI: ${uri}`,
                    });
                    return;
                }
            } catch {
                res.status(400).json({
                    error: 'invalid_redirect_uri',
                    error_description: `Malformed redirect_uri: ${uri}`,
                });
                return;
            }
        }

        const client_id = generateToken(16);
        const registration: ClientRegistration = {
            client_id,
            client_name: client_name ?? 'Unknown Client',
            redirect_uris,
            grant_types: grant_types ?? ['authorization_code'],
            response_types: response_types ?? ['code'],
            token_endpoint_auth_method: 'none',
        };
        registeredClients.set(client_id, registration);

        logger.info(`OAuth/register: registered client ${client_id} ("${registration.client_name}")`);

        res.status(201).json({
            client_id: registration.client_id,
            client_name: registration.client_name,
            redirect_uris: registration.redirect_uris,
            grant_types: registration.grant_types,
            response_types: registration.response_types,
            token_endpoint_auth_method: registration.token_endpoint_auth_method,
        });
    });

    // -----------------------------------------------------------------------
    // Authorization Endpoint – GET  (display the sign-in form)
    // -----------------------------------------------------------------------
    router.get('/authorize', (req: Request, res: Response): void => {
        const q = req.query as Record<string, string>;
        const {
            client_id,
            redirect_uri,
            response_type,
            code_challenge,
            code_challenge_method,
            scope,
            state,
        } = q;

        if (!client_id || !redirect_uri || !response_type || !code_challenge) {
            res.status(400).send(
                'Missing required parameters: client_id, redirect_uri, response_type, code_challenge'
            );
            return;
        }
        if (response_type !== 'code') {
            res.status(400).send('Only response_type=code is supported');
            return;
        }
        if (code_challenge_method && code_challenge_method !== 'S256') {
            res.status(400).send('Only code_challenge_method=S256 is supported');
            return;
        }

        const client = registeredClients.get(client_id);
        if (client && !client.redirect_uris.includes(redirect_uri)) {
            res.status(400).send('redirect_uri is not registered for this client');
            return;
        }

        res.send(
            buildAuthorizeHtml({
                client_id,
                redirect_uri,
                code_challenge,
                code_challenge_method: code_challenge_method ?? 'S256',
                scope: scope ?? '',
                state: state ?? '',
            })
        );
    });

    // -----------------------------------------------------------------------
    // Authorization Endpoint – POST  (process the sign-in form submission)
    // -----------------------------------------------------------------------
    router.post('/authorize', async (req: Request, res: Response): Promise<void> => {
        const {
            client_id,
            redirect_uri,
            code_challenge,
            code_challenge_method,
            scope,
            state,
            username,
            pat,
        } = req.body as Record<string, string>;

        if (!client_id || !redirect_uri || !code_challenge || !username || !pat) {
            res.status(400).send('Missing required parameters');
            return;
        }

        const client = registeredClients.get(client_id);
        if (client && !client.redirect_uris.includes(redirect_uri)) {
            res.status(400).send('redirect_uri is not registered for this client');
            return;
        }

        logger.info(`OAuth/authorize: verifying Docker Hub credentials for user "${username}"`);
        const hubToken = await dockerHubLogin(username, pat);

        if (!hubToken) {
            res.send(
                buildAuthorizeHtml({
                    client_id,
                    redirect_uri,
                    code_challenge,
                    code_challenge_method: code_challenge_method ?? 'S256',
                    scope: scope ?? '',
                    state: state ?? '',
                    error: 'Invalid Docker Hub username or Personal Access Token.',
                })
            );
            return;
        }

        const code = generateToken(32);
        authCodes.set(code, {
            client_id,
            redirect_uri,
            code_challenge,
            code_challenge_method: code_challenge_method ?? 'S256',
            scope: scope ?? '',
            state: state || undefined,
            username,
            hub_token: hubToken,
            expires_at: Date.now() + 5 * 60_000, // 5 minutes
        });

        const callback = new URL(redirect_uri);
        callback.searchParams.set('code', code);
        if (state) callback.searchParams.set('state', state);

        logger.info(`OAuth/authorize: issued authorization code for user "${username}"`);
        res.redirect(302, callback.toString());
    });

    // -----------------------------------------------------------------------
    // Token Endpoint
    // -----------------------------------------------------------------------
    router.post('/token', (req: Request, res: Response): void => {
        const { grant_type, code, redirect_uri, client_id, code_verifier } =
            req.body as Record<string, string>;

        if (grant_type !== 'authorization_code') {
            res.status(400).json({
                error: 'unsupported_grant_type',
                error_description: 'Only authorization_code grant type is supported',
            });
            return;
        }

        if (!code || !code_verifier || !client_id) {
            res.status(400).json({
                error: 'invalid_request',
                error_description: 'code, code_verifier, and client_id are required',
            });
            return;
        }

        const ac = authCodes.get(code);
        if (!ac) {
            res.status(400).json({
                error: 'invalid_grant',
                error_description: 'Authorization code not found or already consumed',
            });
            return;
        }

        if (Date.now() > ac.expires_at) {
            authCodes.delete(code);
            res.status(400).json({
                error: 'invalid_grant',
                error_description: 'Authorization code has expired',
            });
            return;
        }

        if (ac.client_id !== client_id) {
            res.status(400).json({
                error: 'invalid_grant',
                error_description: 'client_id does not match the one used during authorization',
            });
            return;
        }

        if (redirect_uri && ac.redirect_uri !== redirect_uri) {
            res.status(400).json({
                error: 'invalid_grant',
                error_description: 'redirect_uri does not match the one used during authorization',
            });
            return;
        }

        if (!verifyPKCE(code_verifier, ac.code_challenge, ac.code_challenge_method)) {
            authCodes.delete(code);
            res.status(400).json({
                error: 'invalid_grant',
                error_description: 'PKCE code_verifier verification failed',
            });
            return;
        }

        // Consume the code (one-time use)
        authCodes.delete(code);

        const access_token = generateToken(32);
        const expires_in = 24 * 3600; // 24 hours
        accessTokens.set(access_token, {
            client_id,
            scope: ac.scope,
            username: ac.username,
            hub_token: ac.hub_token,
            expires_at: Date.now() + expires_in * 1000,
        });

        logger.info(`OAuth/token: issued access token for user "${ac.username}"`);

        res.json({
            access_token,
            token_type: 'bearer',
            expires_in,
            scope: ac.scope,
        });
    });

    return router;
}

// ---------------------------------------------------------------------------
// Token lookup (used by the MCP endpoint middleware)
// ---------------------------------------------------------------------------

/**
 * Look up a previously issued MCP access token.
 * Returns null if the token is unknown or has expired.
 */
export function lookupOAuthToken(token: string): OAuthTokenData | null {
    const data = accessTokens.get(token);
    if (!data) return null;
    if (Date.now() > data.expires_at) {
        accessTokens.delete(token);
        return null;
    }
    return data;
}

// ---------------------------------------------------------------------------
// Express middleware – enforce Bearer token on protected routes
// ---------------------------------------------------------------------------

/**
 * Express middleware that requires a valid MCP OAuth access token.
 *
 * On success, the validated token payload is attached to the request as
 * `req.oauthToken` so downstream handlers can read the Docker Hub credentials.
 *
 * On failure, responds with HTTP 401 and a WWW-Authenticate header pointing the
 * client toward the OAuth authorization server, as required by the MCP spec.
 */
export function requireOAuthMiddleware(issuerBaseUrl: string) {
    return (req: Request, res: Response, next: NextFunction): void => {
        const authHeader = req.headers.authorization ?? '';

        if (!authHeader.toLowerCase().startsWith('bearer ')) {
            res.status(401)
                .header(
                    'WWW-Authenticate',
                    `Bearer realm="${issuerBaseUrl}", error="invalid_token", error_description="Bearer token required"`
                )
                .json({
                    error: 'unauthorized',
                    error_description: 'A valid Bearer access token is required',
                });
            return;
        }

        const token = authHeader.slice('bearer '.length).trim();
        const tokenData = lookupOAuthToken(token);

        if (!tokenData) {
            res.status(401)
                .header(
                    'WWW-Authenticate',
                    `Bearer realm="${issuerBaseUrl}", error="invalid_token", error_description="Token invalid or expired"`
                )
                .json({
                    error: 'invalid_token',
                    error_description: 'The access token is invalid or has expired',
                });
            return;
        }

        (req as Request & { oauthToken: OAuthTokenData }).oauthToken = tokenData;
        next();
    };
}
