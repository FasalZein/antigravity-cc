<script lang="ts">
	import ProgressBar from './ProgressBar.svelte';
	import { dashboard, openModal } from '$lib/stores/dashboard.svelte';
	import type { AntigravityAccount, CodexAccount } from '$lib/api/quota';

	interface Props {
		account: AntigravityAccount | CodexAccount;
		type: 'antigravity' | 'codex';
		lastUpdated?: string;
	}

	let { account, type, lastUpdated = '' }: Props = $props();
	
	const isAntigravity = $derived(type === 'antigravity');
	const antigravityAccount = $derived(account as AntigravityAccount);
	const codexAccount = $derived(account as CodexAccount);
	
	function handleDetailsClick() {
		openModal(account.email);
	}
</script>

<div class="account-card glass-card rounded-xl overflow-hidden" data-email={account.email}>
	<!-- Account Header -->
	<div class="px-5 py-4 border-b border-white/5 flex items-center justify-between">
		<div class="min-w-0 flex-1">
			{#if isAntigravity}
				<div class="flex items-center gap-2">
					<p class="text-sm text-text-primary truncate {dashboard.emailsHidden ? 'blur-email' : ''}">{account.email}</p>
					{#if antigravityAccount.planType}
						<span class="text-xs px-2 py-0.5 bg-accent-primary/20 text-accent-primary rounded-full font-medium">{antigravityAccount.planType}</span>
					{/if}
				</div>
				{#if account.error}
					<p class="text-xs text-status-critical mt-1">{account.error}</p>
				{:else}
					<div class="flex items-center gap-3 mt-1">
						<span class="text-xs text-text-muted">{antigravityAccount.quotas?.length || Object.keys(antigravityAccount.groupQuotas || {}).length} models</span>
						<span class="text-xs text-text-muted">•</span>
						<span class="text-xs text-text-muted">Updated {lastUpdated}</span>
					</div>
				{/if}
			{:else}
				<div class="flex items-center gap-2">
					<p class="text-sm text-text-primary truncate {dashboard.emailsHidden ? 'blur-email' : ''}">{account.email}</p>
					{#if codexAccount.planType}
						<span class="text-xs px-2 py-0.5 bg-accent-primary/20 text-accent-primary rounded-full font-medium">{codexAccount.planType}</span>
					{/if}
				</div>
				{#if account.error}
					<p class="text-xs text-status-critical mt-1">{account.error}</p>
				{:else}
					<div class="flex items-center gap-3 mt-1">
						<span class="text-xs text-text-muted">Codex CLI</span>
						{#if codexAccount.limitReached}
							<span class="text-xs text-status-critical">• Limit Reached</span>
						{/if}
					</div>
				{/if}
			{/if}
		</div>
		{#if isAntigravity && !account.error}
			<button 
				onclick={handleDetailsClick} 
				class="p-2 rounded-lg hover:bg-surface-3 text-text-muted hover:text-text-primary transition-colors" 
				title="View all models"
			>
				<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
				</svg>
			</button>
		{/if}
	</div>

	{#if !account.error}
		<!-- Quota Bars -->
		<div class="p-5 space-y-4">
			{#if isAntigravity}
				{#if antigravityAccount.groupQuotas?.['Claude']}
					<ProgressBar 
						label="Claude" 
						percent={antigravityAccount.groupQuotas['Claude'].minPercent} 
						resetIn={antigravityAccount.groupQuotas['Claude'].resetIn}
						resetTime={antigravityAccount.groupQuotas['Claude'].resetTime}
					/>
				{/if}
				{#if antigravityAccount.groupQuotas?.['Gemini Pro']}
					<ProgressBar 
						label="Gemini Pro" 
						percent={antigravityAccount.groupQuotas['Gemini Pro'].minPercent} 
						resetIn={antigravityAccount.groupQuotas['Gemini Pro'].resetIn}
						resetTime={antigravityAccount.groupQuotas['Gemini Pro'].resetTime}
					/>
				{/if}
				{#if antigravityAccount.groupQuotas?.['Gemini Flash']}
					<ProgressBar 
						label="Gemini Flash" 
						percent={antigravityAccount.groupQuotas['Gemini Flash'].minPercent} 
						resetIn={antigravityAccount.groupQuotas['Gemini Flash'].resetIn}
						resetTime={antigravityAccount.groupQuotas['Gemini Flash'].resetTime}
					/>
				{/if}
			{:else}
				<ProgressBar 
					label="Session (5h)" 
					percent={codexAccount.sessionPercent} 
					resetIn={codexAccount.sessionResetIn}
					resetTime={codexAccount.sessionResetTime}
				/>
				<ProgressBar 
					label="Weekly" 
					percent={codexAccount.weeklyPercent} 
					resetIn={codexAccount.weeklyResetIn}
					resetTime={codexAccount.weeklyResetTime}
				/>
			{/if}
		</div>
	{/if}
</div>
