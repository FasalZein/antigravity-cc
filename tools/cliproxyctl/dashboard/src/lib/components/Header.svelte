<script lang="ts">
	import { dashboard, setActiveTab, toggleEmailVisibility, loadQuota, openSettings, formatCountdown } from '$lib/stores/dashboard.svelte';
	import CountdownRing from './CountdownRing.svelte';
	
	function handleTabClick(tab: 'antigravity' | 'codex' | 'gemini') {
		setActiveTab(tab);
	}
	
	async function handleRefresh() {
		await loadQuota(true);
	}
</script>

<header class="glass sticky top-0 z-50 border-b border-white/5">
	<div class="max-w-7xl mx-auto px-4 py-3">
		<div class="flex items-center justify-between">
			<!-- Logo & Title -->
			<div class="flex items-center gap-2">
				<img src="/ai-pill.avif" alt="AI-Pill" class="w-14 h-14 rounded-lg">
				<div>
					<h1 class="text-lg font-semibold text-white tracking-tight">AI-Pill War Room</h1>
					<p class="text-xs text-text-muted">Quota Command Center</p>
				</div>
			</div>

			<!-- Provider Tabs -->
			<div class="flex items-center gap-2">
				<button 
					onclick={() => handleTabClick('antigravity')} 
					class="tab-btn flex items-center gap-2 px-3 py-2 rounded-lg border border-white/10 text-sm font-medium {dashboard.activeTab === 'antigravity' ? 'active' : 'text-text-secondary hover:text-text-primary'}"
				>
					<img src="/antigravity.svg" alt="" class="h-5 w-5">
					<span class="hidden sm:inline">Antigravity</span>
				</button>
				<button 
					onclick={() => handleTabClick('codex')} 
					class="tab-btn flex items-center gap-2 px-3 py-2 rounded-lg border border-white/10 text-sm font-medium {dashboard.activeTab === 'codex' ? 'active' : 'text-text-secondary hover:text-text-primary'}"
				>
					<img src="/codex.svg" alt="" class="h-5 w-5">
					<span class="hidden sm:inline">Codex</span>
				</button>
				<button 
					onclick={() => handleTabClick('gemini')} 
					class="tab-btn flex items-center gap-2 px-3 py-2 rounded-lg border border-white/10 text-sm font-medium {dashboard.activeTab === 'gemini' ? 'active' : 'text-text-secondary hover:text-text-primary'}"
				>
					<img src="/gemini-cli.svg" alt="" class="h-5 w-5">
					<span class="hidden sm:inline">Gemini CLI</span>
				</button>
			</div>

			<!-- Controls -->
			<div class="flex items-center gap-3">
				<!-- Hide Emails -->
				<button 
					onclick={toggleEmailVisibility} 
					class="p-2 rounded-lg hover:bg-surface-3 text-text-secondary hover:text-text-primary transition-colors" 
					title="Toggle email visibility"
				>
					{#if dashboard.emailsHidden}
						<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88" />
						</svg>
					{:else}
						<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z" />
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
						</svg>
					{/if}
				</button>

				<!-- Settings -->
				<button 
					onclick={openSettings} 
					class="p-2 rounded-lg hover:bg-surface-3 text-text-secondary hover:text-text-primary transition-colors" 
					title="Settings"
				>
					<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a6.759 6.759 0 010 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 010-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28z" />
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
					</svg>
				</button>

				<!-- Countdown Ring -->
				<CountdownRing seconds={dashboard.countdown} maxSeconds={dashboard.settings.refreshInterval} />

				<!-- Refresh -->
				<button 
					onclick={handleRefresh} 
					disabled={dashboard.refreshing}
					class="flex items-center gap-2 px-4 py-2 bg-accent-primary/10 hover:bg-accent-primary/20 border border-accent-primary/30 rounded-lg text-accent-primary text-sm font-medium transition-colors disabled:opacity-50"
				>
					<svg class="w-4 h-4 {dashboard.refreshing ? 'spin' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
					</svg>
					<span class="hidden sm:inline">Refresh</span>
				</button>
			</div>
		</div>
	</div>
</header>
