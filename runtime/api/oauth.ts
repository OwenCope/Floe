//
//  oauth.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Raycast OAuth PKCE client. The browser flow and token storage run in the Swift app over the bridge.
import { ctx, request } from "../bridge";

export const RedirectMethod = { Web: "web", App: "app", AppURI: "appURI" } as const;

function redirectURI(): string {
  // Floe cannot receive Raycast raycast.com or raycast:// redirects, so every method uses the app scheme.
  return `floe://oauth?package_name=${ctx.manifest.name}`;
}

const unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
function randomString(length: number): string {
  const values = crypto.getRandomValues(new Uint8Array(length));
  let out = "";
  for (const value of values) out += unreserved[value % unreserved.length];
  return out;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function s256Challenge(verifier: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64url(new Uint8Array(hash));
}

export type AuthorizationRequestOptions = {
  endpoint: string;
  clientId: string;
  scope: string;
  extraParameters?: Record<string, string>;
};

export class AuthorizationRequest {
  endpoint: string;
  clientId: string;
  scope: string;
  extraParameters: Record<string, string>;
  codeVerifier: string;
  codeChallenge: string;
  state: string;
  redirectURI: string;

  constructor(init: AuthorizationRequestOptions & { codeVerifier: string; codeChallenge: string; state: string; redirectURI: string }) {
    this.endpoint = init.endpoint;
    this.clientId = init.clientId;
    this.scope = init.scope;
    this.extraParameters = init.extraParameters ?? {};
    this.codeVerifier = init.codeVerifier;
    this.codeChallenge = init.codeChallenge;
    this.state = init.state;
    this.redirectURI = init.redirectURI;
  }

  toURL(): string {
    const url = new URL(this.endpoint);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("code_challenge", this.codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
    url.searchParams.set("client_id", this.clientId);
    url.searchParams.set("redirect_uri", this.redirectURI);
    url.searchParams.set("scope", this.scope);
    url.searchParams.set("state", this.state);
    for (const [key, value] of Object.entries(this.extraParameters)) url.searchParams.set(key, value);
    return url.toString();
  }
}

export type TokenSetInit = {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
  expiresIn?: number;
  scope?: string;
  updatedAt?: Date;
};

export class TokenSet {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
  expiresIn?: number;
  scope?: string;
  updatedAt: Date;

  constructor(init: TokenSetInit) {
    this.accessToken = init.accessToken;
    this.refreshToken = init.refreshToken;
    this.idToken = init.idToken;
    this.expiresIn = init.expiresIn;
    this.scope = init.scope;
    this.updatedAt = init.updatedAt ?? new Date();
  }

  isExpired(): boolean {
    if (this.expiresIn === undefined) return false;
    return Date.now() >= this.updatedAt.getTime() + this.expiresIn * 1000 - 10000;
  }
}

type RawTokenResponse = {
  access_token: string;
  refresh_token?: string;
  id_token?: string;
  expires_in?: number;
  scope?: string;
};

function toPlainTokens(input: TokenSet | TokenSetInit | RawTokenResponse): Record<string, unknown> {
  if (input instanceof TokenSet) {
    return {
      accessToken: input.accessToken,
      refreshToken: input.refreshToken,
      idToken: input.idToken,
      expiresIn: input.expiresIn,
      scope: input.scope,
      updatedAt: input.updatedAt.toISOString(),
    };
  }
  const record = input as Record<string, unknown>;
  const updatedAt = record.updatedAt instanceof Date
    ? record.updatedAt.toISOString()
    : typeof record.updatedAt === "string"
      ? record.updatedAt
      : new Date().toISOString();
  if (typeof record.access_token === "string") {
    return {
      accessToken: record.access_token,
      refreshToken: record.refresh_token,
      idToken: record.id_token,
      expiresIn: record.expires_in,
      scope: record.scope,
      updatedAt,
    };
  }
  return {
    accessToken: record.accessToken,
    refreshToken: record.refreshToken,
    idToken: record.idToken,
    expiresIn: record.expiresIn,
    scope: record.scope,
    updatedAt,
  };
}

export type PKCEClientOptions = {
  redirectMethod: (typeof RedirectMethod)[keyof typeof RedirectMethod];
  providerName: string;
  providerIcon?: string;
  providerId?: string;
  description?: string;
};

export class PKCEClient {
  private options: PKCEClientOptions;

  constructor(options: PKCEClientOptions) {
    this.options = options;
  }

  private get providerId(): string {
    return this.options.providerId ?? this.options.providerName;
  }

  async authorizationRequest(options: AuthorizationRequestOptions): Promise<AuthorizationRequest> {
    const codeVerifier = randomString(64);
    const codeChallenge = await s256Challenge(codeVerifier);
    return new AuthorizationRequest({ ...options, codeVerifier, codeChallenge, state: randomString(32), redirectURI: redirectURI() });
  }

  async authorize(requestOrOptions: AuthorizationRequest | { url: string }): Promise<{ authorizationCode: string }> {
    const url = requestOrOptions instanceof AuthorizationRequest ? requestOrOptions.toURL() : requestOrOptions.url;
    const state = requestOrOptions instanceof AuthorizationRequest ? requestOrOptions.state : (requestOrOptions as { state?: string }).state;
    const response = await request("oauth.authorize", { url, state, providerName: this.options.providerName });
    const callback = typeof response === "string" ? response : (response?.url as string);
    const params = new URL(callback).searchParams;
    const error = params.get("error");
    if (error) throw new Error(params.get("error_description") ?? error);
    if (state !== undefined && params.get("state") !== state) throw new Error("OAuth state mismatch");
    const code = params.get("code");
    if (!code) throw new Error("OAuth callback has no authorization code");
    return { authorizationCode: code };
  }

  async setTokens(tokens: TokenSet | TokenSetInit | RawTokenResponse): Promise<void> {
    await request("oauth.setTokens", { providerId: this.providerId, tokens: toPlainTokens(tokens) });
  }

  async getTokens(): Promise<TokenSet | undefined> {
    const stored = await request("oauth.getTokens", { providerId: this.providerId });
    if (stored === null || stored === undefined) return undefined;
    return new TokenSet({ ...stored, updatedAt: new Date(stored.updatedAt) });
  }

  async removeTokens(): Promise<void> {
    await request("oauth.removeTokens", { providerId: this.providerId });
  }
}

export const OAuth = { RedirectMethod, PKCEClient, TokenSet, AuthorizationRequest };
