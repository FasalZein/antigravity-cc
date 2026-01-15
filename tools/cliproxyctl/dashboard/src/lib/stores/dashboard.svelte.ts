import { fetchQuota, invalidateCache, type QuotaData } from '$lib/api/quota';

// Settings type
interface Settings {
	refreshInterval: number;
	autoRefresh: boolean;
}

// Create a single state object (can be exported because we mutate properties, not reassign)
export const dashboard = $state({
	data: null as QuotaData | null,
	loading: true,
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
function getAverageForGroup(groupName: string): { avg: number; resetIn: string } {
	if (!dashboard.data?.accounts?.length) return { avg: 0, resetIn: '' };
	
	let total = 0;
	let count = 0;
	let resetIn = '';
	
	for (const account of dashboard.data.accounts) {
		const group = account.groupQuotas?.[groupName];
		if (group) {
			total += group.minPercent;
			count++;
			if (!resetIn && group.resetIn) {
				resetIn = group.resetIn;
			}
		}
	}
	
	return { avg: count > 0 ? total / count : 0, resetIn };
}

export function getClaudeStats() { return getAverageForGroup('Claude'); }
export function getGeminiProStats() { return getAverageForGroup('Gemini Pro'); }
export function getGeminiFlashStats() { return getAverageForGroup('Gemini Flash'); }

export function getCodexSessionStats() {
	if (!dashboard.data?.codexAccounts?.length) return { avg: 0, resetIn: '' };
	const avg = dashboard.data.codexAccounts.reduce((sum, a) => sum + (a.sessionPercent || 0), 0) / dashboard.data.codexAccounts.length;
	return { avg, resetIn: dashboard.data.codexAccounts[0]?.sessionResetIn || '' };
}

export function getCodexWeeklyStats() {
	if (!dashboard.data?.codexAccounts?.length) return { avg: 0, resetIn: '' };
	const avg = dashboard.data.codexAccounts.reduce((sum, a) => sum + (a.weeklyPercent || 0), 0) / dashboard.data.codexAccounts.length;
	return { avg, resetIn: dashboard.data.codexAccounts[0]?.weeklyResetIn || '' };
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

export async function loadQuota(forceRefresh = false): Promise<void> {
	if (forceRefresh) {
		dashboard.refreshing = true;
	} else {
		dashboard.loading = true;
	}
	dashboard.error = null;
	
	try {
		if (forceRefresh) {
			invalidateCache();
		}
		dashboard.data = await fetchQuota(forceRefresh);
		dashboard.countdown = dashboard.settings.refreshInterval;
	} catch (e) {
		dashboard.error = e instanceof Error ? e.message : 'Unknown error';
	} finally {
		dashboard.loading = false;
		dashboard.refreshing = false;
	}
}

export function startCountdown(): () => void {
	const timer = setInterval(() => {
		if (!dashboard.settings.autoRefresh) return;
		
		dashboard.countdown--;
		if (dashboard.countdown <= 0) {
			loadQuota(true);
		}
	}, 1000);
	
	return () => clearInterval(timer);
}

export function formatCountdown(seconds: number): string {
	const m = Math.floor(seconds / 60);
	return `${m}m`;
}
