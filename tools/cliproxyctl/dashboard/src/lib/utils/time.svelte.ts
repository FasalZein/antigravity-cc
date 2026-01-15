// Time utilities for countdown calculations
// Using exported object with mutable properties (Svelte 5 pattern)

// Shared reactive state - mutate properties, don't reassign
export const timeState = $state({
	tick: 0,
	now: Date.now()
});

/**
 * Calculate remaining time from an ISO timestamp
 * Returns formatted string like "2h 30m" or "45m" or "Now"
 */
export function getTimeRemaining(resetTime: string | undefined, currentTime: number = Date.now()): string {
	if (!resetTime) return '';
	
	try {
		const target = new Date(resetTime).getTime();
		const diff = target - currentTime;
		
		if (diff <= 0) return 'Now';
		
		const hours = Math.floor(diff / (1000 * 60 * 60));
		const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
		
		if (hours > 24) {
			const days = Math.floor(hours / 24);
			const remainingHours = hours % 24;
			return `${days}d ${remainingHours}h`;
		}
		
		if (hours > 0) {
			return `${hours}h ${minutes}m`;
		}
		
		return `${minutes}m`;
	} catch {
		return '';
	}
}

/**
 * Start the global countdown timer
 * Updates every second for real-time display
 */
export function startCountdownTimer(): () => void {
	const timer = setInterval(() => {
		timeState.tick += 1;
		timeState.now = Date.now();
	}, 1000); // Update every second
	
	return () => clearInterval(timer);
}
