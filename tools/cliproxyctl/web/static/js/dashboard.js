// AI-Pill War Room Dashboard JavaScript

let dashboardData = {};
let countdown = 300;
let countdownInterval;
let isRefreshing = false;
let emailsHidden = false;
let currentProvider = 'antigravity';

const REFRESH_INTERVAL = 300;
const CIRCLE_CIRCUMFERENCE = 113.1;
const RING_CIRCUMFERENCE = 150.8;

// Initialize dashboard data from server
function initDashboard(data) {
    dashboardData = data;
}

// Switch provider tabs
function switchProvider(provider) {
    currentProvider = provider;

    // Update tabs
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.remove('active');
        btn.classList.add('text-text-secondary');
    });
    document.getElementById('tab-' + provider).classList.add('active');
    document.getElementById('tab-' + provider).classList.remove('text-text-secondary');

    // Update content
    document.querySelectorAll('.provider-content').forEach(el => el.classList.remove('active'));
    document.getElementById('content-' + provider).classList.add('active');
}

// Toggle email visibility
function toggleEmailVisibility() {
    emailsHidden = !emailsHidden;
    const emails = document.querySelectorAll('.email-text');
    const icon = document.getElementById('eyeIcon');

    emails.forEach(el => {
        el.classList.toggle('blur-email', emailsHidden);
    });

    icon.innerHTML = emailsHidden
        ? `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88" />`
        : `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />`;
}

// Show model details modal
function showDetails(email) {
    const account = dashboardData.accounts.find(a => a.email === email);
    if (!account || !account.quotas) return;

    const modal = document.getElementById('modal');
    const title = document.getElementById('modalTitle');
    const content = document.getElementById('modalContent');

    title.textContent = emailsHidden ? '••••••••@••••' : email;

    const sortedQuotas = [...account.quotas].sort((a, b) => {
        const groupOrder = { 'Claude': 0, 'Gemini Pro': 1, 'Gemini Flash': 2, 'Other': 3 };
        const groupDiff = (groupOrder[a.group] || 99) - (groupOrder[b.group] || 99);
        if (groupDiff !== 0) return groupDiff;
        return a.percentage - b.percentage;
    });

    let currentGroup = '';
    let html = '';

    sortedQuotas.forEach(q => {
        if (q.group !== currentGroup) {
            if (currentGroup) html += '</div>';
            currentGroup = q.group;
            html += `<div class="mb-4"><p class="text-xs text-text-muted uppercase tracking-wider mb-3 font-medium">${q.group}</p>`;
        }

        const statusClass = q.percentage >= 50 ? 'text-status-healthy' : q.percentage >= 20 ? 'text-status-caution' : 'text-status-critical';
        const bgClass = q.percentage >= 50 ? 'bg-status-healthy' : q.percentage >= 20 ? 'bg-status-caution' : 'bg-status-critical';

        html += `
            <div class="flex items-center justify-between py-2 border-b border-white/5 last:border-0">
                <div class="flex-1 min-w-0 pr-4">
                    <p class="text-sm text-text-primary truncate font-mono" title="${q.name}">${q.name}</p>
                </div>
                <div class="flex items-center gap-4 flex-shrink-0">
                    <span class="text-xs text-text-muted font-mono">${q.resetIn}</span>
                    <div class="w-20 h-1.5 bg-surface-3 rounded-full overflow-hidden">
                        <div class="h-full rounded-full ${bgClass}" style="width: ${q.percentage}%"></div>
                    </div>
                    <span class="text-sm font-mono w-12 text-right ${statusClass}">${q.percentage.toFixed(0)}%</span>
                </div>
            </div>
        `;
    });

    if (currentGroup) html += '</div>';
    content.innerHTML = html;

    modal.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
}

function closeModal(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('modal').classList.add('hidden');
    document.body.style.overflow = '';
}

function getStatusColor(percentage) {
    if (percentage >= 50) return '#10b981';
    if (percentage >= 20) return '#f59e0b';
    return '#ef4444';
}

function updateRing(ringId, textId, avgId, percentage) {
    const ring = document.getElementById(ringId);
    const text = document.getElementById(textId);
    const avg = document.getElementById(avgId);

    if (ring && text && avg) {
        const offset = RING_CIRCUMFERENCE * (1 - percentage / 100);
        ring.style.strokeDashoffset = offset;
        ring.style.stroke = getStatusColor(percentage);
        text.textContent = percentage.toFixed(0) + '%';
        avg.textContent = percentage.toFixed(0) + '%';
        avg.className = `text-2xl font-bold font-mono ${percentage >= 50 ? 'text-status-healthy' : percentage >= 20 ? 'text-status-caution' : 'text-status-critical'}`;
    }
}

function updateAverages() {
    const groups = { 'Claude': { values: [], resetTimes: [] }, 'Gemini Pro': { values: [], resetTimes: [] }, 'Gemini Flash': { values: [], resetTimes: [] } };

    dashboardData.accounts.forEach(account => {
        if (account.groupQuotas) {
            Object.entries(account.groupQuotas).forEach(([name, gq]) => {
                if (groups[name] !== undefined) {
                    groups[name].values.push(gq.minPercent);
                    if (gq.resetIn && gq.resetIn !== '—' && gq.resetIn !== '') {
                        groups[name].resetTimes.push(gq.resetIn);
                    }
                }
            });
        }
    });

    const ringMap = {
        'Claude': ['claudeRing', 'claudeRingText', 'claudeAvg', 'claudeReset'],
        'Gemini Pro': ['geminiProRing', 'geminiProRingText', 'geminiProAvg', 'geminiProReset'],
        'Gemini Flash': ['geminiFlashRing', 'geminiFlashRingText', 'geminiFlashAvg', 'geminiFlashReset']
    };

    Object.entries(groups).forEach(([name, data]) => {
        if (data.values.length > 0) {
            const avg = data.values.reduce((a, b) => a + b, 0) / data.values.length;
            const [ringId, textId, avgId, resetId] = ringMap[name];
            updateRing(ringId, textId, avgId, avg);

            // Update reset time (show earliest reset)
            const resetEl = document.getElementById(resetId);
            if (resetEl) {
                if (data.resetTimes.length > 0) {
                    // Sort reset times and show earliest
                    const earliest = data.resetTimes.sort(compareResetTimes)[0];
                    resetEl.textContent = '↻ ' + earliest;
                    resetEl.className = 'text-xs text-accent-primary font-mono px-1.5 py-0.5 bg-accent-primary/10 rounded';
                } else {
                    resetEl.textContent = '—';
                    resetEl.className = 'text-xs text-text-muted font-mono px-1.5 py-0.5 bg-surface-3 rounded';
                }
            }
        }
    });
}

// Compare reset time strings (returns -1 if a < b, 1 if a > b, 0 if equal)
function compareResetTimes(a, b) {
    const parseReset = (s) => {
        if (!s || s === '—' || s === 'now') return 0;
        let total = 0;
        const parts = s.split(' ');
        parts.forEach(p => {
            const match = p.match(/^(\d+)([dhm])/);
            if (match) {
                const n = parseInt(match[1]);
                const unit = match[2];
                if (unit === 'd') total += n * 24 * 60;
                else if (unit === 'h') total += n * 60;
                else if (unit === 'm') total += n;
            }
        });
        return total;
    };
    return parseReset(a) - parseReset(b);
}

function updateCountdown() {
    const circle = document.getElementById('countdownCircle');
    const text = document.getElementById('countdownText');

    if (circle && text) {
        const offset = CIRCLE_CIRCUMFERENCE * (1 - countdown / REFRESH_INTERVAL);
        circle.style.strokeDashoffset = offset;

        if (countdown >= 60) {
            const mins = Math.floor(countdown / 60);
            text.textContent = `${mins}m`;
        } else {
            text.textContent = `${countdown}s`;
        }
    }
}

function startCountdown() {
    countdown = REFRESH_INTERVAL;
    updateCountdown();

    if (countdownInterval) clearInterval(countdownInterval);

    countdownInterval = setInterval(() => {
        countdown--;
        updateCountdown();
        if (countdown <= 0) autoRefresh();
    }, 1000);
}

async function autoRefresh() {
    if (isRefreshing) return;

    try {
        const response = await fetch('/api/quota');
        const newData = await response.json();

        if (newData.lastUpdated !== dashboardData.lastUpdated) {
            dashboardData = newData;
            document.getElementById('lastUpdatedBadge').textContent = dashboardData.lastUpdated;
            document.getElementById('totalAccounts').textContent = dashboardData.totalAccounts;
            updateAverages();
        }
    } catch (error) {
        console.error('Auto-refresh failed:', error);
    }

    startCountdown();
}

async function refreshData() {
    if (isRefreshing) return;
    isRefreshing = true;

    const btn = document.getElementById('refreshBtn');
    const icon = document.getElementById('refreshIcon');

    btn.disabled = true;
    btn.classList.add('opacity-50');
    icon.classList.add('animate-spin');

    if (countdownInterval) clearInterval(countdownInterval);
    document.getElementById('countdownText').textContent = '...';

    try {
        const response = await fetch('/api/quota?refresh=true');
        dashboardData = await response.json();

        document.getElementById('lastUpdatedBadge').textContent = dashboardData.lastUpdated;
        document.getElementById('totalAccounts').textContent = dashboardData.totalAccounts;
        updateAverages();
    } catch (error) {
        console.error('Refresh failed:', error);
    } finally {
        isRefreshing = false;
        btn.disabled = false;
        btn.classList.remove('opacity-50');
        icon.classList.remove('animate-spin');
        startCountdown();
    }
}

// Event listeners
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') closeModal();
});

document.addEventListener('DOMContentLoaded', () => {
    updateAverages();
    startCountdown();
});
