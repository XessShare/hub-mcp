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

import express, { Express, Request, Response } from 'express';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { McpServer as Server } from '@modelcontextprotocol/sdk/server/mcp.js';
import {
    JSONRPC_VERSION,
    METHOD_NOT_FOUND,
    INTERNAL_ERROR,
} from '@modelcontextprotocol/specification/schema/2025-06-18/schema';
import { ScoutAPI } from './scout';
import { Asset } from './asset';
import { Repos } from './repos';
import { Accounts } from './accounts';
import { Search } from './search';
import { logger } from './logger';
import { createOAuthRouter, requireOAuthMiddleware, OAuthTokenData } from './oauth';

const STDIO_OPTION = 'stdio';
const STREAMABLE_HTTP_OPTION = 'http';

export class HubMCPServer {
    private readonly server: Server;
    private readonly assets: Asset[];
    private readonly username?: string;
    private readonly patToken?: string;

    constructor(username?: string, patToken?: string) {
        this.username = username;
        this.patToken = patToken;

        this.server = new Server(
            {
                name: 'dockerhub-mcp-server',
                version: '1.0.0',
            },
            {
                capabilities: {
                    tools: {},
                },
            }
        );

        this.assets = [
            new Repos(this.server, {
                name: 'repos',
                host: 'https://hub.docker.com/v2',
                auth: {
                    type: 'pat',
                    token: patToken,
                    username: username,
                },
            }),
            new Accounts(this.server, {
                name: 'accounts',
                host: 'https://hub.docker.com/v2',
                auth: {
                    type: 'pat',
                    token: patToken,
                    username: username,
                },
            }),
            new Search(this.server, {
                name: 'search',
                host: 'https://hub.docker.com/api/search',
            }),
            new ScoutAPI(this.server, {
                name: 'scout',
                host: 'https://api.scout.docker.com',
                auth: {
                    type: 'pat',
                    token: patToken,
                    username: username,
                },
            }),
        ];
        for (const asset of this.assets) {
            asset.RegisterTools();
        }
    }

    async run(port: number, transportType: string): Promise<void> {
        switch (transportType) {
            case STDIO_OPTION: {
                const transport = new StdioServerTransport();
                await this.server.connect(transport);
                logger.info('mcp server listening over stdio');
                break;
            }
            case STREAMABLE_HTTP_OPTION: {
                const app = express();
                app.use(express.json());

                // Derive the issuer base URL from the port.
                // In production the server is typically fronted by a TLS proxy and
                // the real base URL should be passed via the HUB_MCP_BASE_URL env var.
                const issuerBaseUrl =
                    process.env.HUB_MCP_BASE_URL ?? `http://localhost:${port}`;

                // Mount OAuth 2.1 endpoints (metadata, register, authorize, token)
                app.use(createOAuthRouter(issuerBaseUrl));

                this.registerRoutes(app, issuerBaseUrl);
                app.listen(port, () => {
                    logger.info(`mcp server listening on port ${port}`);
                    logger.info(
                        `OAuth authorization server available at ${issuerBaseUrl}/.well-known/oauth-authorization-server`
                    );
                });
                break;
            }
        }
    }

    /**
     * Create a per-request MCP server instance configured with the given credentials.
     *
     * Using a fresh server per request ensures that the Docker Hub credentials
     * (obtained through the OAuth flow) are scoped to the individual HTTP request
     * without leaking between concurrent callers.
     *
     * @param username   Docker Hub username.
     * @param token      Either a Docker Hub JWT (type='bearer') or a PAT (type='pat').
     * @param tokenType  'bearer' when coming from an OAuth access token; 'pat' for raw PAT.
     */
    private createMCPServerInstance(
        username?: string,
        token?: string,
        tokenType: 'bearer' | 'pat' = 'pat'
    ): Server {
        const server = new Server(
            { name: 'dockerhub-mcp-server', version: '1.0.0' },
            { capabilities: { tools: {} } }
        );

        const assets = [
            new Repos(server, {
                name: 'repos',
                host: 'https://hub.docker.com/v2',
                auth: { type: tokenType, token, username },
            }),
            new Accounts(server, {
                name: 'accounts',
                host: 'https://hub.docker.com/v2',
                auth: { type: tokenType, token, username },
            }),
            new Search(server, {
                name: 'search',
                host: 'https://hub.docker.com/api/search',
            }),
            new ScoutAPI(server, {
                name: 'scout',
                host: 'https://api.scout.docker.com',
                auth: { type: tokenType, token, username },
            }),
        ];

        for (const asset of assets) {
            asset.RegisterTools();
        }

        return server;
    }

    private registerRoutes(app: Express, issuerBaseUrl: string) {
        const oauthMiddleware = requireOAuthMiddleware(issuerBaseUrl);

        // ------------------------------------------------------------------
        // POST /mcp  – main MCP endpoint (requires a valid OAuth access token)
        // ------------------------------------------------------------------
        app.post('/mcp', oauthMiddleware, async (req: Request, res: Response) => {
            const sanitizedBody = JSON.stringify(req.body).replace(/\n|\r/g, '');
            logger.info(`received mcp request: ${sanitizedBody}`);

            // The OAuth middleware has already validated the token and attached it.
            const oauthToken = (req as Request & { oauthToken: OAuthTokenData }).oauthToken;

            try {
                // Create a per-request MCP server that uses the caller's Docker Hub
                // JWT (hub_token) directly as a Bearer token for Hub API calls.
                const mcpServer = this.createMCPServerInstance(
                    oauthToken.username,
                    oauthToken.hub_token,
                    'bearer'
                );

                const transport = new StreamableHTTPServerTransport({
                    sessionIdGenerator: undefined,
                    enableJsonResponse: true,
                });

                await mcpServer.connect(transport);
                await transport.handleRequest(req, res, req.body);
            } catch (error) {
                logger.info(`error handling mcp request: ${error}`);
                if (!res.headersSent) {
                    res.status(500).json({
                        jsonrpc: JSONRPC_VERSION,
                        error: {
                            code: INTERNAL_ERROR,
                            message: 'Internal server error',
                        },
                        id: null,
                    });
                }
            }
        });

        app.get('/mcp', async (_req: Request, res: Response) => {
            logger.info('received get mcp request');
            res.writeHead(405).end(
                JSON.stringify({
                    jsonrpc: JSONRPC_VERSION,
                    error: {
                        code: METHOD_NOT_FOUND,
                        message: 'Method not allowed.',
                    },
                    id: null,
                })
            );
        });

        app.delete('/mcp', async (_req: Request, res: Response) => {
            logger.info('received delete mcp request');
            res.writeHead(405).end(
                JSON.stringify({
                    jsonrpc: JSONRPC_VERSION,
                    error: {
                        code: METHOD_NOT_FOUND,
                        message: 'Method not allowed.',
                    },
                    id: null,
                })
            );
        });
    }

    public GetAssets(): Asset[] {
        return this.assets;
    }
}
