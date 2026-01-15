import { fetchAntigravity, fetchCodex, invalidateCache, type QuotaData, type AntigravityAccount, type CodexAccount } from '$lib/api/quota';
import { startCountdownTimer } from '$lib/utils/time.svelte';

// Settings type
interface Settings {
	refreshInterval: number;
	autoRefresh: boolean;
}

// Create a single state object (can be exported because we mutate properties, not reassign)
export const dashboard = $state({
	data: null as QuotaData | null,
	loading: true,
	loadingAntigravity: true,
	loadingCodex: true,
	error: null as string | null,
	activeTab: 'antigravity' as 'antigravity' | 'codex' | 'gemini',
	emailsHidden: false,
	countdown: 300,
	refreshing: false,
	modalOpen: false,
	modalEmail: '',
	settingsOpen: false,
	settings: {
		refreshInterval: 300,
		autoRefresh: true
	} as Settings,
	initialized: false
});

// Helper to check if we're in browser
function isBrowser(): boolean {
	return typeof window !== 'undefined';
}

// Initialize from localStorage (call this once on mount)
export function initializeFromStorage(): void {
	if (!isBrowser() || dashboard.initialized) return;
	
	const savedTab = localStorage.getItem('dashboard-tab');
	if (savedTab === 'antigravity' || savedTab === 'codex' || savedTab === 'gemini') {
		dashboard.activeTab = savedTab;
	}
	const savedHidden = localStorage.getItem('dashboard-emails-hidden');
	if (savedHidden === 'true') {
		dashboard.emailsHidden = true;
	}
	const savedSettings = localStorage.getItem('dashboard-settings');
	if (savedSettings) {
		try {
			const parsed = JSON.parse(savedSettings);
			dashboard.settings = { ...dashboard.settings, ...parsed };
			dashboard.countdown = dashboard.settings.refreshInterval;
		} catch {}
	}
	dashboard.initialized = true;
}

// Computed values
function getAverageForGroup(groupName: string): { avg: number; resetIn: string; resetTime: string } {
	if (!dashboard.data?.accounts?.length) return { avg: 0, resetIn: '', resetTime: '' };
	
	let total = 0;
	let count = 0;
	let resetIn = '';
	let resetTime = '';
	
	for (const account of dashboard.data.accounts) {
		const group = account.groupQuotas?.[groupName];
		if (group) {
			total += group.minPercent;
			count++;
			// Track earliest reset time
			if (group.resetTime && (!resetTime || group.resetTime < resetTime)) {
				resetTime = group.resetTime;
				resetIn = group.resetIn;
			}
		}
	}
	
	return { avg: count > 0 ? total / count : 0, resetIn, resetTime };
}

export function getClaudeStats() { return getAverageForGroup('Claude'); }
export function getGeminiProStats() { return getAverageForGroup('Gemini Pro'); }
export function getGeminiFlashStats() { return getAverageForGroup('Gemini Flash'); }

export function getCodexSessionStats() {
	if (!dashboard.data?.codexAccounts?.length) return { avg: 0, resetIn: '', resetTime: '' };
	const avg = dashboard.data.codexAccounts.reduce((sum, a) => sum + (a.sessionPercent || 0), 0) / dashboard.data.codexAccounts.length;
	// Find earliest reset
	let earliest = dashboard.data.codexAccounts[0];
	for (const acc of dashboard.data.codexAccounts) {
		if (acc.sessionResetTime && (!earliest.sessionResetTime || acc.sessionResetTime < earliest.sessionResetTime)) {
			earliest = acc;
		}
	}
	return { avg, resetIn: earliest?.sessionResetIn || '', resetTime: earliest?.sessionResetTime || '' };
}

export function getCodexWeeklyStats() {
	if (!dashboard.data?.codexAccounts?.length) return { avg: 0, resetIn: '', resetTime: '' };
	const avg = dashboard.data.codexAccounts.reduce((sum, a) => sum + (a.weeklyPercent || 0), 0) / dashboard.data.codexAccounts.length;
	// Find earliest reset
	let earliest = dashboard.data.codexAccounts[0];
	for (const acc of dashboard.data.codexAccounts) {
		if (acc.weeklyResetTime && (!earliest.weeklyResetTime || acc.weeklyResetTime < earliest.weeklyResetTime)) {
			earliest = acc;
		}
	}
	return { avg, resetIn: earliest?.weeklyResetIn || '', resetTime: earliest?.weeklyResetTime || '' };
}

export function setActiveTab(tab: 'antigravity' | 'codex' | 'gemini') {
	dashboard.activeTab = tab;
	if (isBrowser()) {
		localStorage.setItem('dashboard-tab', tab);
	}
}

export function toggleEmailVisibility() {
	dashboard.emailsHidden = !dashboard.emailsHidden;
	if (isBrowser()) {
		localStorage.setItem('dashboard-emails-hidden', String(dashboard.emailsHidden));
	}
}

export function openModal(email: string) {
	dashboard.modalEmail = email;
	dashboard.modalOpen = true;
}

export function closeModal() {
	dashboard.modalOpen = false;
	dashboard.modalEmail = '';
}

export function openSettings() {
	dashboard.settingsOpen = true;
}

export function closeSettings() {
	dashboard.settingsOpen = false;
}

export function updateSettings(newSettings: Partial<Settings>) {
	dashboard.settings = { ...dashboard.settings, ...newSettings };
	dashboard.countdown = dashboard.settings.refreshInterval;
	if (isBrowser()) {
		localStorage.setItem('dashboard-settings', JSON.stringify(dashboard.settings));
	}
}

// Load both providers in parallel but update UI as each completes
export async function loadQuota(forceRefresh = false): Promise<void> {
	if (forceRefresh) {
		dashboard.refreshing = true;
		invalidateCache();
	} else {
		dashboard.loading = true;
		dashboard.loadingAntigravity = true;
		dashboard.loadingCodex = true;
	}
	dashboard.error = null;
	
	// Initialize data structure if needed
	if (!dashboard.data) {
		dashboard.data = {
			accounts: [],
			codexAccounts: [],
			lastUpdated: '',
			totalAntigravity: 0,
			totalCodex: 0
		};
	}
	
	// Load both providers in parallel - UI updates as each completes
	const antigravityPromise = fetchAntigravity(forceRefresh)
		.then(result => {
			dashboard.data!.accounts = result.accounts;
			dashboard.data!.totalAntigravity = result.totalAntigravity;
			dashboard.data!.lastUpdated = result.lastUpdated;
			dashboard.loadingAntigravity = false;
			dashboard.loading = false; // Show UI as soon as first provider loads
		})
		.catch(e => {
			console.error('Antigravity fetch error:', e);
			dashboard.loadingAntigravity = false;
		});

	const codexPromise = fetchCodex(forceRefresh)
		.then(result => {
			dashboard.data!.codexAccounts = result.codexAccounts;
			dashboard.data!.totalCodex = result.totalCodex;
			if (result.lastUpdated) dashboard.data!.lastUpdated = result.lastUpdated;
			dashboard.loadingCodex = false;
			dashboard.loading = false;
		})
		.catch(e => {
			console.error('Codex fetch error:', e);
			dashboard.loadingCodex = false;
		});

	await Promise.all([antigravityPromise, codexPromise]);
	
	dashboard.countdown = dashboard.settings.refreshInterval;
	dashboard.loading = false;
	dashboard.refreshing = false;
}

export function startCountdown(): () => void {
	// Start the live countdown timer for reset times
	const stopLiveCountdown = startCountdownTimer();
	
	const timer = setInterval(() => {
		if (!dashboard.settings.autoRefresh) return;
		
		dashboard.countdown--;
		if (dashboard.countdown <= 0) {
			loadQuota(true);
		}
	}, 1000);
	
	return () => {
		clearInterval(timer);
		stopLiveCountdown();
	};
}

export function formatCountdown(seconds: number): string {
	const m = Math.floor(seconds / 60);
	return `${m}m`;
}
