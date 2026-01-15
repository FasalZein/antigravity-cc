<script lang="ts">
	import { dashboard, closeSettings, updateSettings } from '$lib/stores/dashboard.svelte';
	
	let refreshInterval = $state(300);
	let autoRefresh = $state(true);
	
	// Sync with store when modal opens
	$effect(() => {
		if (dashboard.settingsOpen) {
			refreshInterval = dashboard.settings.refreshInterval;
			autoRefresh = dashboard.settings.autoRefresh;
		}
	});
	
	function handleBackdropClick(e: MouseEvent) {
		if (e.target === e.currentTarget) {
			closeSettings();
		}
	}
	
	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			closeSettings();
		}
	}
	
	function handleSave() {
		updateSettings({
			refreshInterval,
			autoRefresh
		});
		closeSettings();
	}
</script>

<svelte:window onkeydown={handleKeydown} />

{#if dashboard.settingsOpen}
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="fixed inset-0 z-50" onclick={handleBackdropClick}>
		<div class="modal-backdrop absolute inset-0"></div>
		<div class="relative flex items-center justify-center min-h-screen p-4">
			<!-- svelte-ignore a11y_click_events_have_key_events -->
			<!-- svelte-ignore a11y_no_static_element_interactions -->
			<div class="modal-enter glass-card rounded-xl shadow-2xl w-full max-w-md overflow-hidden" onclick={(e) => e.stopPropagation()}>
				<div class="flex items-center justify-between px-5 py-4 border-b border-white/5">
					<h3 class="text-sm font-medium text-white">Settings</h3>
					<button onclick={closeSettings} class="p-2 rounded-lg hover:bg-surface-3 text-text-muted hover:text-text-primary transition-colors" title="Close">
						<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M6 18L18 6M6 6l12 12" />
						</svg>
					</button>
				</div>
				<div class="p-5 space-y-6">
					<!-- Auto Refresh Toggle -->
					<div class="flex items-center justify-between">
						<div>
							<p class="text-sm text-text-primary font-medium">Auto Refresh</p>
							<p class="text-xs text-text-muted mt-0.5">Automatically refresh quota data</p>
						</div>
						<button 
							onclick={() => autoRefresh = !autoRefresh}
							class="relative w-11 h-6 rounded-full transition-colors {autoRefresh ? 'bg-accent-primary' : 'bg-surface-4'}"
						>
							<span class="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full transition-transform {autoRefresh ? 'translate-x-5' : ''}"></span>
						</button>
					</div>
					
					<!-- Refresh Interval -->
					<div>
						<label class="block text-sm text-text-primary font-medium mb-2">Refresh Interval</label>
						<select 
							bind:value={refreshInterval}
							disabled={!autoRefresh}
							class="w-full bg-surface-3 border border-white/10 rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-accent-primary disabled:opacity-50"
						>
							<option value={60}>1 minute</option>
							<option value={180}>3 minutes</option>
							<option value={300}>5 minutes</option>
							<option value={600}>10 minutes</option>
						</select>
					</div>
					
					<!-- Storage Info -->
					<div class="bg-surface-2/50 rounded-lg p-3">
						<p class="text-xs text-text-muted">
							<span class="text-accent-primary">●</span> Settings are saved to localStorage
						</p>
					</div>
				</div>
				
				<div class="px-5 py-4 border-t border-white/5 flex justify-end gap-3">
					<button 
						onclick={closeSettings}
						class="px-4 py-2 text-sm text-text-secondary hover:text-text-primary transition-colors"
					>
						Cancel
					</button>
					<button 
						onclick={handleSave}
						class="px-4 py-2 bg-accent-primary hover:bg-accent-primary/90 rounded-lg text-sm font-medium text-white transition-colors"
					>
						Save
					</button>
				</div>
			</div>
		</div>
	</div>
{/if}
