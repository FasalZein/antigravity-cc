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
}

export interface AntigravityAccount {
	email: string;
	error?: string;
	quotas: ModelQuota[];
	groupQuotas: Record<string, GroupQuota>;
}

export interface CodexAccount {
	email: string;
	sessionPercent: number;
	weeklyPercent: number;
	sessionResetIn: string;
	weeklyResetIn: string;
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

// Cache with TTL
let cache: { data: QuotaData | null; timestamp: number } = { data: null, timestamp: 0 };
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

export async function fetchQuota(forceRefresh = false): Promise<QuotaData> {
	const now = Date.now();
	
	if (!forceRefresh && cache.data && (now - cache.timestamp) < CACHE_TTL) {
		return cache.data;
	}

	const endpoint = forceRefresh ? '/api/quota?refresh=true' : '/api/quota';
	const response = await fetch(endpoint);
	
	if (!response.ok) {
		throw new Error(`Failed to fetch quota: ${response.statusText}`);
	}

	const data: QuotaData = await response.json();
	cache = { data, timestamp: now };
	return data;
}

export function invalidateCache(): void {
	cache = { data: null, timestamp: 0 };
}

export function getCacheAge(): number {
	if (!cache.timestamp) return 0;
	return Date.now() - cache.timestamp;
}
