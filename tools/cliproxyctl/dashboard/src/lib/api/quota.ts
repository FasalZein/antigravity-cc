// Types matching Go backend structs directly

export interface ModelQuota {
	name: string;
	percentage: number;
	resetTime: string;
	resetIn: string;
	group: string;
}

export interface GroupQuota {
	name: string;
	minPercent: number;
	icon: string;
	color: string;
	resetIn: string;
	resetTime?: string;
}

export interface AntigravityAccount {
	email: string;
	error?: string;
	planType?: string;
	quotas: ModelQuota[];
	groupQuotas: Record<string, GroupQuota>;
}

export interface CodexAccount {
	email: string;
	sessionPercent: number;
	weeklyPercent: number;
	sessionResetIn: string;
	sessionResetTime?: string;
	weeklyResetIn: string;
	weeklyResetTime?: string;
	planType: string;
	limitReached: boolean;
	error?: string;
}

export interface QuotaData {
	accounts: AntigravityAccount[];
	codexAccounts: CodexAccount[];
	lastUpdated: string;
	totalAntigravity: number;
	totalCodex: number;
}

// Separate caches for each provider
let antigravityCache: { data: AntigravityAccount[] | null; timestamp: number; lastUpdated: string } = { data: null, timestamp: 0, lastUpdated: '' };
let codexCache: { data: CodexAccount[] | null; timestamp: number; lastUpdated: string } = { data: null, timestamp: 0, lastUpdated: '' };
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

export async function fetchAntigravity(forceRefresh = false): Promise<{ accounts: AntigravityAccount[]; totalAntigravity: number; lastUpdated: string }> {
	const now = Date.now();
	
	if (!forceRefresh && antigravityCache.data && (now - antigravityCache.timestamp) < CACHE_TTL) {
		return { accounts: antigravityCache.data, totalAntigravity: antigravityCache.data.length, lastUpdated: antigravityCache.lastUpdated };
	}

	const response = await fetch('/api/quota/antigravity');
	if (!response.ok) {
		throw new Error(`Failed to fetch Antigravity: ${response.statusText}`);
	}

	const data = await response.json();
	antigravityCache = { data: data.accounts || [], timestamp: now, lastUpdated: data.lastUpdated || '' };
	return { accounts: data.accounts || [], totalAntigravity: data.totalAntigravity || 0, lastUpdated: data.lastUpdated || '' };
}

export async function fetchCodex(forceRefresh = false): Promise<{ codexAccounts: CodexAccount[]; totalCodex: number; lastUpdated: string }> {
	const now = Date.now();
	
	if (!forceRefresh && codexCache.data && (now - codexCache.timestamp) < CACHE_TTL) {
		return { codexAccounts: codexCache.data, totalCodex: codexCache.data.length, lastUpdated: codexCache.lastUpdated };
	}

	const response = await fetch('/api/quota/codex');
	if (!response.ok) {
		throw new Error(`Failed to fetch Codex: ${response.statusText}`);
	}

	const data = await response.json();
	codexCache = { data: data.codexAccounts || [], timestamp: now, lastUpdated: data.lastUpdated || '' };
	return { codexAccounts: data.codexAccounts || [], totalCodex: data.totalCodex || 0, lastUpdated: data.lastUpdated || '' };
}

// Legacy combined fetch (for backward compatibility)
export async function fetchQuota(forceRefresh = false): Promise<QuotaData> {
	const [antigravity, codex] = await Promise.all([
		fetchAntigravity(forceRefresh),
		fetchCodex(forceRefresh)
	]);
	
	return {
		accounts: antigravity.accounts,
		codexAccounts: codex.codexAccounts,
		lastUpdated: antigravity.lastUpdated || codex.lastUpdated,
		totalAntigravity: antigravity.totalAntigravity,
		totalCodex: codex.totalCodex
	};
}

export function invalidateCache(): void {
	antigravityCache = { data: null, timestamp: 0, lastUpdated: '' };
	codexCache = { data: null, timestamp: 0, lastUpdated: '' };
}

export function getCacheAge(): number {
	return Math.max(
		antigravityCache.timestamp ? Date.now() - antigravityCache.timestamp : 0,
		codexCache.timestamp ? Date.now() - codexCache.timestamp : 0
	);
}
