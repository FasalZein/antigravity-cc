<script lang="ts">
	import { onMount } from 'svelte';
	import Header from '$lib/components/Header.svelte';
	import Footer from '$lib/components/Footer.svelte';
	import SummaryCard from '$lib/components/SummaryCard.svelte';
	import RingCard from '$lib/components/RingCard.svelte';
	import AccountCard from '$lib/components/AccountCard.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import Settings from '$lib/components/Settings.svelte';
	import SkeletonCard from '$lib/components/SkeletonCard.svelte';
	import { dashboard, loadQuota, startCountdown, initializeFromStorage, getClaudeStats, getGeminiProStats, getGeminiFlashStats, getCodexSessionStats, getCodexWeeklyStats } from '$lib/stores/dashboard.svelte';

	onMount(() => {
		initializeFromStorage();
		loadQuota();
		const stopCountdown = startCountdown();
		return stopCountdown;
	});
</script>

<Header />

<main class="max-w-7xl mx-auto px-4 py-6">
	<!-- Antigravity Content -->
	{#if dashboard.activeTab === 'antigravity'}
		{#if dashboard.loadingAntigravity && !dashboard.data?.accounts?.length}
			<!-- Skeleton Loading -->
			<div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
				<SkeletonCard type="summary" />
				<SkeletonCard type="ring" />
				<SkeletonCard type="ring" />
				<SkeletonCard type="ring" />
			</div>
			<div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
				{#each Array(4) as _}
					<SkeletonCard type="account" />
				{/each}
			</div>
		{:else if dashboard.data && dashboard.data.totalAntigravity > 0}
			<!-- Summary Row -->
			<div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
				<SummaryCard 
					label="Accounts" 
					value={dashboard.data.totalAntigravity} 
					subLabel={dashboard.data.lastUpdated} 
				/>
				<RingCard 
					label="Claude" 
					percent={getClaudeStats().avg} 
					resetIn={getClaudeStats().resetIn}
					resetTime={getClaudeStats().resetTime}
				/>
				<RingCard 
					label="Gemini Pro" 
					percent={getGeminiProStats().avg} 
					resetIn={getGeminiProStats().resetIn}
					resetTime={getGeminiProStats().resetTime}
				/>
				<RingCard 
					label="Gemini Flash" 
					percent={getGeminiFlashStats().avg} 
					resetIn={getGeminiFlashStats().resetIn}
					resetTime={getGeminiFlashStats().resetTime}
				/>
			</div>

			<!-- Accounts Grid -->
			<div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
				{#each dashboard.data.accounts as account}
					<AccountCard {account} type="antigravity" lastUpdated={dashboard.data.lastUpdated} />
				{/each}
			</div>
		{:else}
			<EmptyState 
				title="No Accounts Found" 
				message="No auth files found in <code class='bg-surface-3 px-2 py-1 rounded font-mono text-xs'>~/.cli-proxy-api/</code>" 
			/>
		{/if}
	{/if}

	<!-- Codex Content -->
	{#if dashboard.activeTab === 'codex'}
		{#if dashboard.loadingCodex && !dashboard.data?.codexAccounts?.length}
			<!-- Skeleton Loading -->
			<div class="grid grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
				<SkeletonCard type="summary" />
				<SkeletonCard type="ring" />
				<SkeletonCard type="ring" />
			</div>
			<div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
				{#each Array(4) as _}
					<SkeletonCard type="account" />
				{/each}
			</div>
		{:else if dashboard.data && dashboard.data.totalCodex > 0}
			<!-- Summary Row -->
			<div class="grid grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
				<SummaryCard 
					label="Accounts" 
					value={dashboard.data.totalCodex} 
					subLabel={dashboard.data.lastUpdated} 
				/>
				<RingCard 
					label="Session (5h)" 
					percent={getCodexSessionStats().avg} 
					resetIn={getCodexSessionStats().resetIn}
					resetTime={getCodexSessionStats().resetTime}
				/>
				<RingCard 
					label="Weekly" 
					percent={getCodexWeeklyStats().avg} 
					resetIn={getCodexWeeklyStats().resetIn}
					resetTime={getCodexWeeklyStats().resetTime}
				/>
			</div>

			<!-- Accounts Grid -->
			<div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
				{#each dashboard.data.codexAccounts as account}
					<AccountCard {account} type="codex" />
				{/each}
			</div>
		{:else}
			<EmptyState 
				icon="/codex.svg"
				title="No Codex Accounts Found" 
				message="No auth files found at <code class='bg-surface-3 px-2 py-1 rounded font-mono text-xs'>~/.cli-proxy-api/codex-*.json</code>"
				hint="Add Codex accounts via CLIProxyAPI"
			/>
		{/if}
	{/if}

	<!-- Gemini CLI Content -->
	{#if dashboard.activeTab === 'gemini'}
		<EmptyState 
			icon="/gemini-cli.svg"
			title="Gemini CLI Quota" 
			message="Gemini CLI quota monitoring coming soon."
			hint="Auth files will be loaded from <code class='bg-surface-3 px-2 py-1 rounded font-mono text-xs'>~/.gemini/</code>"
		/>
	{/if}
</main>

<Footer />
<Modal />
<Settings />
