<script lang="ts">
	import { dashboard, closeModal } from '$lib/stores/dashboard.svelte';
	
	function handleBackdropClick(e: MouseEvent) {
		if (e.target === e.currentTarget) {
			closeModal();
		}
	}
	
	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			closeModal();
		}
	}
	
	// Get account data for modal
	const getAccount = () => dashboard.data?.accounts.find(a => a.email === dashboard.modalEmail);
	
	// Group and sort quotas like the old template
	function getGroupedQuotas() {
		const account = getAccount();
		if (!account?.quotas) return [];
		
		const groupOrder: Record<string, number> = { 'Claude': 0, 'Gemini Pro': 1, 'Gemini Flash': 2, 'Other': 3 };
		
		const sorted = [...account.quotas].sort((a, b) => {
			const groupDiff = (groupOrder[a.group] ?? 99) - (groupOrder[b.group] ?? 99);
			if (groupDiff !== 0) return groupDiff;
			return a.percentage - b.percentage;
		});
		
		const groups: { name: string; quotas: typeof sorted }[] = [];
		let currentGroup = '';
		
		for (const q of sorted) {
			if (q.group !== currentGroup) {
				currentGroup = q.group;
				groups.push({ name: currentGroup, quotas: [] });
			}
			groups[groups.length - 1].quotas.push(q);
		}
		
		return groups;
	}
	
	function getStatusClass(pct: number): string {
		if (pct >= 50) return 'text-status-healthy';
		if (pct >= 20) return 'text-status-caution';
		return 'text-status-critical';
	}
	
	function getBgClass(pct: number): string {
		if (pct >= 50) return 'bg-status-healthy';
		if (pct >= 20) return 'bg-status-caution';
		return 'bg-status-critical';
	}
</script>

<svelte:window onkeydown={handleKeydown} />

{#if dashboard.modalOpen}
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="fixed inset-0 z-50" onclick={handleBackdropClick}>
		<div class="modal-backdrop absolute inset-0"></div>
		<div class="relative flex items-center justify-center min-h-screen p-4">
			<!-- svelte-ignore a11y_click_events_have_key_events -->
			<!-- svelte-ignore a11y_no_static_element_interactions -->
			<div class="modal-enter glass-card rounded-xl shadow-2xl w-full max-w-lg max-h-[80vh] overflow-hidden" onclick={(e) => e.stopPropagation()}>
				<div class="flex items-center justify-between px-5 py-4 border-b border-white/5">
					<h3 class="text-sm font-medium text-white font-mono truncate {dashboard.emailsHidden ? 'blur-email' : ''}">{dashboard.modalEmail}</h3>
					<button onclick={closeModal} class="p-2 rounded-lg hover:bg-surface-3 text-text-muted hover:text-text-primary transition-colors" title="Close">
						<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M6 18L18 6M6 6l12 12" />
						</svg>
					</button>
				</div>
				<div class="p-5 overflow-y-auto max-h-[60vh]">
					{#if getGroupedQuotas().length > 0}
						{#each getGroupedQuotas() as group}
							<div class="mb-4">
								<p class="text-xs text-text-muted uppercase tracking-wider mb-3 font-medium">{group.name}</p>
								{#each group.quotas as quota}
									<div class="flex items-center justify-between py-2 border-b border-white/5 last:border-0">
										<div class="flex-1 min-w-0 pr-4">
											<p class="text-sm text-text-primary truncate font-mono" title={quota.name}>{quota.name}</p>
										</div>
										<div class="flex items-center gap-4 flex-shrink-0">
											<span class="text-xs text-text-muted font-mono">{quota.resetIn}</span>
											<div class="w-20 h-1.5 bg-surface-3 rounded-full overflow-hidden">
												<div class="h-full rounded-full {getBgClass(quota.percentage)}" style="width: {quota.percentage}%"></div>
											</div>
											<span class="text-sm font-mono w-12 text-right {getStatusClass(quota.percentage)}">{Math.round(quota.percentage)}%</span>
										</div>
									</div>
								{/each}
							</div>
						{/each}
					{:else}
						{@const account = getAccount()}
						{#if account?.groupQuotas}
							{#each Object.entries(account.groupQuotas) as [name, quota]}
								<div class="flex items-center justify-between py-2 px-3 rounded-lg bg-surface-2/50 mb-2">
									<span class="text-sm text-text-secondary truncate flex-1">{name}</span>
									<div class="flex items-center gap-3">
										{#if quota.resetIn}
											<span class="text-xs text-accent-primary font-mono">↻ {quota.resetIn}</span>
										{/if}
										<span class="font-mono text-sm {getStatusClass(quota.minPercent)}">
											{Math.round(quota.minPercent)}%
										</span>
									</div>
								</div>
							{/each}
						{:else}
							<p class="text-text-muted text-center py-4">No quota data available</p>
						{/if}
					{/if}
				</div>
			</div>
		</div>
	</div>
{/if}
