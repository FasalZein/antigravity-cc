package cli

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"cliproxyctl/web"
	"github.com/spf13/cobra"
)

const (
	quotaAPIURL   = "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
	projectAPIURL = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
	tokenURL      = "https://oauth2.googleapis.com/token"
	clientID      = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
	clientSecret  = "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"
	userAgent     = "antigravity/1.11.3 Darwin/arm64"
)

// AuthFile represents the Antigravity auth file structure
type AuthFile struct {
	AccessToken  string `json:"access_token"`
	Email        string `json:"email"`
	Expired      string `json:"expired,omitempty"`
	ExpiresIn    int    `json:"expires_in,omitempty"`
	RefreshToken string `json:"refresh_token,omitempty"`
	Timestamp    int64  `json:"timestamp,omitempty"`
	Type         string `json:"type,omitempty"`
}

// TokenResponse from OAuth refresh
type TokenResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int    `json:"expires_in"`
	TokenType   string `json:"token_type"`
}

// QuotaAPIResponse from Google's API
type QuotaAPIResponse struct {
	Models map[string]ModelInfo `json:"models"`
}

// ModelInfo contains quota information
type ModelInfo struct {
	QuotaInfo *QuotaInfoAPI `json:"quotaInfo,omitempty"`
}

// QuotaInfoAPI contains the actual quota data
type QuotaInfoAPI struct {
	RemainingFraction float64 `json:"remainingFraction,omitempty"`
	ResetTime         string  `json:"resetTime,omitempty"`
}

// ProjectResponse from loadCodeAssist API
type ProjectResponse struct {
	CloudAICompanionProject string `json:"cloudaicompanionProject,omitempty"`
}

// ModelQuota represents parsed quota for a model
type ModelQuota struct {
	Name       string  `json:"name"`
	Percentage float64 `json:"percentage"`
	ResetTime  string  `json:"resetTime"`
	ResetIn    string  `json:"resetIn"`
	Group      string  `json:"group"`
}

// AccountQuota represents quota for an account
type AccountQuota struct {
	Email       string                `json:"email"`
	Error       string                `json:"error,omitempty"`
	Quotas      []ModelQuota          `json:"quotas"`
	GroupQuotas map[string]GroupQuota `json:"groupQuotas"`
}

// GroupQuota represents aggregated quota for a model group
type GroupQuota struct {
	Name       string  `json:"name"`
	MinPercent float64 `json:"minPercent"`
	Icon       string  `json:"icon"`
	Color      string  `json:"color"`
	ResetIn    string  `json:"resetIn"`
}

// ============================================================================
// Codex Quota Types
// ============================================================================

// CodexAuthFile represents the Codex CLI auth file structure (flat, like Antigravity)
type CodexAuthFile struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	IDToken      string `json:"id_token"`
	Email        string `json:"email"`
	Expired      string `json:"expired,omitempty"`
	AccountID    string `json:"account_id,omitempty"`
	Type         string `json:"type,omitempty"`
}

// CodexUsageResponse from OpenAI's usage API
type CodexUsageResponse struct {
	RateLimit *CodexRateLimitInfo `json:"rate_limit"`
}

// CodexRateLimitInfo contains rate limit windows
type CodexRateLimitInfo struct {
	PrimaryWindow   *CodexWindowInfo `json:"primary_window"`   // Session (5-hour window)
	SecondaryWindow *CodexWindowInfo `json:"secondary_window"` // Weekly
}

// CodexWindowInfo contains window quota info
type CodexWindowInfo struct {
	UsedPercent int   `json:"used_percent"`
	ResetAt     int64 `json:"reset_at"` // Unix timestamp
}

const (
	codexUsageAPI     = "https://chatgpt.com/backend-api/wham/usage"
	codexTokenURL     = "https://auth.openai.com/oauth/token"
	codexClientID     = "app_EMoamEEZ73f0CkXaXp7hrann"
)

// CodexAccountQuota represents quota for a Codex account
type CodexAccountQuota struct {
	Email              string  `json:"email"`
	Error              string  `json:"error,omitempty"`
	PlanType           string  `json:"planType,omitempty"`
	SessionPercent     float64 `json:"sessionPercent"`     // Remaining (100 - used)
	SessionResetIn     string  `json:"sessionResetIn"`
	WeeklyPercent      float64 `json:"weeklyPercent"`      // Remaining (100 - used)
	WeeklyResetIn      string  `json:"weeklyResetIn"`
	LimitReached       bool    `json:"limitReached"`
}

// DashboardData for web template
type DashboardData struct {
	Accounts        []AccountQuota      `json:"accounts"`
	CodexAccounts   []CodexAccountQuota `json:"codexAccounts"`
	LastUpdated     string              `json:"lastUpdated"`
	TotalAccounts   int                 `json:"totalAccounts"`
	TotalCodex      int                 `json:"totalCodex"`
}

var (
	quotaWebMode     bool
	quotaPort        int
	quotaOpenBrowser bool

	// Cache for web mode
	quotaCacheMu    sync.RWMutex
	quotaCachedData *DashboardData
	quotaCacheTime  time.Time
	quotaCacheTTL   = 5 * time.Minute
)

func NewQuotaCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "quota",
		Short: "Check Antigravity quota",
		Long: `Check Antigravity quota for all accounts.

Modes:
  CLI (default): Displays quota in terminal with colored output
  Web (--web):   Starts HTTP server with Tailwind CSS dashboard

This command reads Antigravity auth files from ~/.cli-proxy-api/
and fetches quota information directly from Google's API.`,
		RunE: runQuota,
	}

	cmd.Flags().BoolVar(&quotaWebMode, "web", false, "Start web server with dashboard")
	cmd.Flags().IntVar(&quotaPort, "port", 8318, "Port for web server")
	cmd.Flags().BoolVar(&quotaOpenBrowser, "open", true, "Open browser automatically (web mode)")

	return cmd
}

func runQuota(cmd *cobra.Command, args []string) error {
	if quotaWebMode {
		return startQuotaWebServer()
	}
	return runQuotaCLI()
}

// ============================================================================
// CLI Mode
// ============================================================================

func runQuotaCLI() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("error getting home directory: %w", err)
	}

	authDir := filepath.Join(homeDir, ".cli-proxy-api")

	files, err := os.ReadDir(authDir)
	if err != nil {
		return fmt.Errorf("error reading auth directory %s: %w", authDir, err)
	}

	fmt.Println("╔════════════════════════════════════════════════════════════════════╗")
	fmt.Println("║           Antigravity Quota Checker (Direct Google API)            ║")
	fmt.Println("╚════════════════════════════════════════════════════════════════════╝")
	fmt.Println()

	client := &http.Client{Timeout: 30 * time.Second}
	accountCount := 0

	for _, file := range files {
		if !strings.HasPrefix(file.Name(), "antigravity-") || !strings.HasSuffix(file.Name(), ".json") {
			continue
		}

		filePath := filepath.Join(authDir, file.Name())
		quotas, email, err := fetchQuotaForFile(client, filePath)
		if err != nil {
			fmt.Printf("❌ %s: %v\n\n", file.Name(), err)
			continue
		}

		accountCount++
		printAccountQuota(email, quotas)
	}

	if accountCount == 0 {
		fmt.Println("No Antigravity auth files found in", authDir)
		fmt.Println("Files should be named: antigravity-*.json")
	}

	return nil
}

// ============================================================================
// Web Server Mode
// ============================================================================

func startQuotaWebServer() error {
	// Parse templates
	tmpl, err := template.New("").Funcs(template.FuncMap{
		"json": func(v interface{}) template.JS {
			b, _ := json.Marshal(v)
			return template.JS(b)
		},
		"multiply": func(a, b int) int {
			return a * b
		},
		"minus": func(a, b float64) float64 {
			return a - b
		},
		"ringOffset": func(percent float64) float64 {
			// Calculate stroke-dashoffset: 150.8 * (1 - percent/100)
			return 150.8 * (1.0 - percent/100.0)
		},
	}).ParseFS(web.Assets, "templates/*.html")
	if err != nil {
		return fmt.Errorf("error parsing templates: %w", err)
	}

	mux := http.NewServeMux()

	// Static files (logos, JS, etc.)
	mux.HandleFunc("/static/", func(w http.ResponseWriter, r *http.Request) {
		// Strip /static/ prefix
		fileName := strings.TrimPrefix(r.URL.Path, "/static/")
		if fileName == "" {
			http.NotFound(w, r)
			return
		}

		// Try static/images first, then static/js
		var content []byte
		var err error
		var contentType string

		switch {
		case strings.HasSuffix(fileName, ".js"):
			content, err = web.Assets.ReadFile("static/js/" + fileName)
			contentType = "application/javascript"
		case strings.HasSuffix(fileName, ".svg"):
			content, err = web.Assets.ReadFile("static/images/" + fileName)
			contentType = "image/svg+xml"
		case strings.HasSuffix(fileName, ".avif"):
			content, err = web.Assets.ReadFile("static/images/" + fileName)
			contentType = "image/avif"
		case strings.HasSuffix(fileName, ".png"):
			content, err = web.Assets.ReadFile("static/images/" + fileName)
			contentType = "image/png"
		case strings.HasSuffix(fileName, ".jpg"), strings.HasSuffix(fileName, ".jpeg"):
			content, err = web.Assets.ReadFile("static/images/" + fileName)
			contentType = "image/jpeg"
		default:
			content, err = web.Assets.ReadFile("static/images/" + fileName)
			contentType = "application/octet-stream"
		}

		if err != nil {
			http.NotFound(w, r)
			return
		}

		w.Header().Set("Content-Type", contentType)
		w.Header().Set("Cache-Control", "public, max-age=86400")
		w.Write(content)
	})

	// Routes
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		data := getQuotaData()
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if err := tmpl.ExecuteTemplate(w, "index.html", data); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
	})

	mux.HandleFunc("/api/quota", func(w http.ResponseWriter, r *http.Request) {
		// Force refresh if requested
		if r.URL.Query().Get("refresh") == "true" {
			quotaCacheMu.Lock()
			quotaCachedData = nil
			quotaCacheMu.Unlock()
		}

		data := getQuotaData()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(data)
	})

	addr := fmt.Sprintf("127.0.0.1:%d", quotaPort)
	url := fmt.Sprintf("http://%s", addr)

	fmt.Printf("🚀 Quota Dashboard starting at %s\n", url)
	fmt.Println("   Press Ctrl+C to stop")
	fmt.Println()

	// Open browser
	if quotaOpenBrowser {
		go func() {
			time.Sleep(500 * time.Millisecond)
			openBrowserURL(url)
		}()
	}

	return http.ListenAndServe(addr, mux)
}

func getQuotaData() *DashboardData {
	quotaCacheMu.RLock()
	if quotaCachedData != nil && time.Since(quotaCacheTime) < quotaCacheTTL {
		defer quotaCacheMu.RUnlock()
		return quotaCachedData
	}
	quotaCacheMu.RUnlock()

	// Fetch fresh data
	data := fetchAllQuotas()

	quotaCacheMu.Lock()
	quotaCachedData = data
	quotaCacheTime = time.Now()
	quotaCacheMu.Unlock()

	return data
}

func fetchAllQuotas() *DashboardData {
	homeDir, _ := os.UserHomeDir()
	authDir := filepath.Join(homeDir, ".cli-proxy-api")

	// Use a shared HTTP client with connection pooling
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        100,
			MaxIdleConnsPerHost: 20,
			IdleConnTimeout:     30 * time.Second,
		},
	}

	var accounts []AccountQuota

	files, err := os.ReadDir(authDir)
	if err == nil {
		// Filter auth files first
		var authFiles []string
		for _, file := range files {
			if strings.HasPrefix(file.Name(), "antigravity-") && strings.HasSuffix(file.Name(), ".json") {
				authFiles = append(authFiles, filepath.Join(authDir, file.Name()))
			}
		}

		if len(authFiles) > 0 {
			// Fetch all accounts concurrently
			var wg sync.WaitGroup
			accountChan := make(chan AccountQuota, len(authFiles))

			for _, filePath := range authFiles {
				wg.Add(1)
				go func(fp string) {
					defer wg.Done()

					quotas, email, err := fetchQuotaForFile(client, fp)

					account := AccountQuota{
						Email:       email,
						Quotas:      quotas,
						GroupQuotas: make(map[string]GroupQuota),
					}

					if err != nil {
						account.Error = err.Error()
					} else {
						// Calculate group quotas
						groups := make(map[string][]ModelQuota)
						for _, q := range quotas {
							groups[q.Group] = append(groups[q.Group], q)
						}

						for group, gQuotas := range groups {
							minPct := 100.0
							earliestReset := ""
							for _, q := range gQuotas {
								if q.Percentage < minPct {
									minPct = q.Percentage
								}
								// Track earliest reset time (for model with lowest quota)
								if q.Percentage < 100 && (earliestReset == "" || q.ResetIn != "" && q.ResetIn != "—") {
									if earliestReset == "" || compareResetTimes(q.ResetIn, earliestReset) {
										earliestReset = q.ResetIn
									}
								}
							}
							account.GroupQuotas[group] = GroupQuota{
								Name:       group,
								MinPercent: minPct,
								Icon:       getGroupIcon(group),
								Color:      getGroupColor(minPct),
								ResetIn:    earliestReset,
							}
						}
					}

					accountChan <- account
				}(filePath)
			}

			// Wait for all goroutines to complete
			go func() {
				wg.Wait()
				close(accountChan)
			}()

			// Collect results
			for account := range accountChan {
				accounts = append(accounts, account)
			}

			// Sort accounts by email for consistent ordering
			sort.Slice(accounts, func(i, j int) bool {
				return accounts[i].Email < accounts[j].Email
			})
		}
	}

	// Fetch Codex quotas (single account from ~/.codex/auth.json)
	codexAccounts := fetchCodexQuotas(client)

	return &DashboardData{
		Accounts:      accounts,
		CodexAccounts: codexAccounts,
		LastUpdated:   time.Now().Format("15:04:05"),
		TotalAccounts: len(accounts),
		TotalCodex:    len(codexAccounts),
	}
}

func getGroupColor(percentage float64) string {
	if percentage >= 50 {
		return "green"
	} else if percentage >= 20 {
		return "yellow"
	}
	return "red"
}

func openBrowserURL(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", url)
	default:
		return
	}
	cmd.Start()
}

// ============================================================================
// Shared Functions
// ============================================================================

func fetchQuotaForFile(client *http.Client, filePath string) ([]ModelQuota, string, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, "", fmt.Errorf("read file: %w", err)
	}

	var authFile AuthFile
	if err := json.Unmarshal(data, &authFile); err != nil {
		return nil, "", fmt.Errorf("parse JSON: %w", err)
	}

	accessToken := authFile.AccessToken

	// Check if token is expired and refresh if needed
	if isTokenExpired(authFile.Expired) && authFile.RefreshToken != "" {
		newToken, err := refreshToken(client, authFile.RefreshToken)
		if err != nil {
			return nil, authFile.Email, fmt.Errorf("refresh token: %w", err)
		}
		accessToken = newToken

		// Update the auth file with new token
		authFile.AccessToken = newToken
		authFile.Expired = time.Now().Add(time.Hour).Format(time.RFC3339)
		if updatedData, err := json.MarshalIndent(authFile, "", "  "); err == nil {
			_ = os.WriteFile(filePath, updatedData, 0644)
		}
	}

	// First get the project ID
	projectID := fetchProjectID(client, accessToken)

	// Then fetch quota
	quotas, err := fetchQuota(client, accessToken, projectID)
	if err != nil {
		return nil, authFile.Email, err
	}

	return quotas, authFile.Email, nil
}

func isTokenExpired(expiredStr string) bool {
	if expiredStr == "" {
		return true
	}

	// Try parsing with fractional seconds
	t, err := time.Parse(time.RFC3339Nano, expiredStr)
	if err != nil {
		// Try without fractional seconds
		t, err = time.Parse(time.RFC3339, expiredStr)
		if err != nil {
			return true
		}
	}

	return time.Now().After(t)
}

func refreshToken(client *http.Client, refreshTokenStr string) (string, error) {
	data := fmt.Sprintf("client_id=%s&client_secret=%s&refresh_token=%s&grant_type=refresh_token",
		clientID, clientSecret, refreshTokenStr)

	req, err := http.NewRequest("POST", tokenURL, strings.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	var tokenResp TokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return "", err
	}

	return tokenResp.AccessToken, nil
}

func fetchProjectID(client *http.Client, accessToken string) string {
	payload := map[string]interface{}{
		"metadata": map[string]string{
			"ideType": "ANTIGRAVITY",
		},
	}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequest("POST", projectAPIURL, bytes.NewReader(body))
	if err != nil {
		return ""
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return ""
	}

	var projectResp ProjectResponse
	if err := json.NewDecoder(resp.Body).Decode(&projectResp); err != nil {
		return ""
	}

	return projectResp.CloudAICompanionProject
}

func fetchQuota(client *http.Client, accessToken, projectID string) ([]ModelQuota, error) {
	payload := map[string]interface{}{}
	if projectID != "" {
		payload["project"] = projectID
	}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequest("POST", quotaAPIURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == 403 {
		return nil, fmt.Errorf("access forbidden (403)")
	}

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	var quotaResp QuotaAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&quotaResp); err != nil {
		return nil, err
	}

	var quotas []ModelQuota
	for name, info := range quotaResp.Models {
		// Only include gemini and claude models
		if !strings.Contains(name, "gemini") && !strings.Contains(name, "claude") {
			continue
		}

		if info.QuotaInfo != nil {
			quota := ModelQuota{
				Name:       name,
				Percentage: info.QuotaInfo.RemainingFraction * 100,
				ResetTime:  info.QuotaInfo.ResetTime,
				ResetIn:    formatResetTime(info.QuotaInfo.ResetTime),
				Group:      getModelGroup(name),
			}
			quotas = append(quotas, quota)
		}
	}

	// Sort by group then name
	sort.Slice(quotas, func(i, j int) bool {
		if quotas[i].Group != quotas[j].Group {
			return quotas[i].Group < quotas[j].Group
		}
		return quotas[i].Name < quotas[j].Name
	})

	return quotas, nil
}

func getModelGroup(name string) string {
	nameLower := strings.ToLower(name)
	if strings.Contains(nameLower, "claude") || strings.Contains(nameLower, "gpt") || strings.Contains(nameLower, "oss") {
		return "Claude"
	}
	if strings.Contains(nameLower, "gemini") && strings.Contains(nameLower, "pro") {
		return "Gemini Pro"
	}
	if strings.Contains(nameLower, "gemini") && strings.Contains(nameLower, "flash") {
		return "Gemini Flash"
	}
	return "Other"
}

func getGroupIcon(group string) string {
	switch group {
	case "Claude":
		return "🧠"
	case "Gemini Pro":
		return "✨"
	case "Gemini Flash":
		return "⚡"
	default:
		return "📊"
	}
}

// ============================================================================
// CLI Output Functions
// ============================================================================

func printAccountQuota(email string, quotas []ModelQuota) {
	fmt.Printf("┌─────────────────────────────────────────────────────────────────────┐\n")
	fmt.Printf("│ 📧 %-65s │\n", email)
	fmt.Printf("├─────────────────────────────────────────────────────────────────────┤\n")

	if len(quotas) == 0 {
		fmt.Printf("│ No quota information available                                      │\n")
		fmt.Printf("└─────────────────────────────────────────────────────────────────────┘\n\n")
		return
	}

	// Group quotas
	groups := make(map[string][]ModelQuota)
	for _, q := range quotas {
		groups[q.Group] = append(groups[q.Group], q)
	}

	// Print by group
	groupOrder := []string{"Claude", "Gemini Pro", "Gemini Flash", "Other"}
	for _, group := range groupOrder {
		groupQuotas, exists := groups[group]
		if !exists || len(groupQuotas) == 0 {
			continue
		}

		// Calculate group minimum percentage
		minPct := 100.0
		for _, q := range groupQuotas {
			if q.Percentage < minPct {
				minPct = q.Percentage
			}
		}

		// Print group header with overall percentage
		icon := getGroupIcon(group)
		bar := makeProgressBar(minPct, 30)
		fmt.Printf("│ %s %-12s %s %5.1f%% remaining        │\n", icon, group, bar, minPct)

		// Print individual models
		for _, q := range groupQuotas {
			fmt.Printf("│   └─ %-25s %5.1f%% │ Reset: %-12s │\n",
				truncateString(q.Name, 25), q.Percentage, q.ResetIn)
		}
	}

	fmt.Printf("└─────────────────────────────────────────────────────────────────────┘\n\n")
}

func makeProgressBar(percentage float64, width int) string {
	filled := int(percentage / 100 * float64(width))
	if filled < 0 {
		filled = 0
	}
	if filled > width {
		filled = width
	}

	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)

	// Color based on percentage
	if percentage >= 50 {
		return "\033[32m" + bar + "\033[0m" // Green
	} else if percentage >= 20 {
		return "\033[33m" + bar + "\033[0m" // Yellow
	} else {
		return "\033[31m" + bar + "\033[0m" // Red
	}
}

func formatResetTime(resetTime string) string {
	if resetTime == "" {
		return "—"
	}

	t, err := time.Parse(time.RFC3339, resetTime)
	if err != nil {
		t, err = time.Parse(time.RFC3339Nano, resetTime)
		if err != nil {
			return resetTime
		}
	}

	now := time.Now()
	diff := t.Sub(now)

	if diff <= 0 {
		return "now"
	}

	hours := int(diff.Hours())
	minutes := int(diff.Minutes()) % 60
	days := hours / 24
	hours = hours % 24

	if days > 0 {
		if hours > 0 {
			return fmt.Sprintf("%dd %dh", days, hours)
		}
		return fmt.Sprintf("%dd", days)
	}
	if hours > 0 {
		if minutes > 0 {
			return fmt.Sprintf("%dh %dm", hours, minutes)
		}
		return fmt.Sprintf("%dh", hours)
	}
	return fmt.Sprintf("%dm", maxInt(1, minutes))
}

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// compareResetTimes returns true if a is earlier than b (both are formatted strings like "1h 30m")
func compareResetTimes(a, b string) bool {
	// Parse reset times to comparable durations
	parseReset := func(s string) int {
		if s == "" || s == "—" || s == "now" {
			return 0
		}
		total := 0
		parts := strings.Fields(s)
		for _, p := range parts {
			n := 0
			unit := ""
			for i, c := range p {
				if c >= '0' && c <= '9' {
					n = n*10 + int(c-'0')
				} else {
					unit = p[i:]
					break
				}
			}
			switch {
			case strings.HasPrefix(unit, "d"):
				total += n * 24 * 60
			case strings.HasPrefix(unit, "h"):
				total += n * 60
			case strings.HasPrefix(unit, "m"):
				total += n
			}
		}
		return total
	}
	return parseReset(a) < parseReset(b)
}

// ============================================================================
// Codex Quota Functions
// ============================================================================

// fetchCodexQuotas fetches quota from ~/.cli-proxy-api/codex-*.json files
func fetchCodexQuotas(client *http.Client) []CodexAccountQuota {
	homeDir, _ := os.UserHomeDir()
	authDir := filepath.Join(homeDir, ".cli-proxy-api")

	files, err := os.ReadDir(authDir)
	if err != nil {
		return nil
	}

	// Filter codex auth files
	var codexFiles []string
	for _, file := range files {
		if strings.HasPrefix(file.Name(), "codex-") && strings.HasSuffix(file.Name(), ".json") {
			codexFiles = append(codexFiles, filepath.Join(authDir, file.Name()))
		}
	}

	if len(codexFiles) == 0 {
		return nil
	}

	var results []CodexAccountQuota

	for _, authPath := range codexFiles {
		data, err := os.ReadFile(authPath)
		if err != nil {
			continue
		}

		var authFile CodexAuthFile
		if err := json.Unmarshal(data, &authFile); err != nil {
			continue
		}

		// Need access token (flat structure, not nested)
		if authFile.AccessToken == "" {
			continue
		}

		accessToken := authFile.AccessToken

		// Check if token is expired and refresh if needed
		if isCodexTokenExpired(accessToken) && authFile.RefreshToken != "" {
			newToken, err := refreshCodexToken(client, authFile.RefreshToken)
			if err == nil {
				accessToken = newToken
				// Update the auth file
				authFile.AccessToken = newToken
				if updatedData, err := json.MarshalIndent(authFile, "", "  "); err == nil {
					_ = os.WriteFile(authPath, updatedData, 0644)
				}
			}
		}

		// Get email from file or id_token
		email := authFile.Email
		if email == "" {
			email = "Codex User"
			if authFile.IDToken != "" {
				if claims := decodeCodexJWT(authFile.IDToken); claims != nil {
					if claims.Email != "" {
						email = claims.Email
					}
				}
			}
		}

		// Fetch quota
		quota, err := fetchCodexUsage(client, accessToken, authFile.AccountID)
		if err != nil {
			results = append(results, CodexAccountQuota{
				Email: email,
				Error: err.Error(),
			})
			continue
		}

		quota.Email = email
		results = append(results, quota)
	}

	return results
}

// CodexUsageAPIResponse from ChatGPT usage API
type CodexUsageAPIResponse struct {
	PlanType  string                 `json:"plan_type,omitempty"`
	RateLimit *CodexRateLimitAPIInfo `json:"rate_limit,omitempty"`
}

// CodexRateLimitAPIInfo from API
type CodexRateLimitAPIInfo struct {
	LimitReached    bool               `json:"limit_reached"`
	PrimaryWindow   *CodexWindowAPIInfo `json:"primary_window,omitempty"`   // Session (5h)
	SecondaryWindow *CodexWindowAPIInfo `json:"secondary_window,omitempty"` // Weekly
}

// CodexWindowAPIInfo from API
type CodexWindowAPIInfo struct {
	UsedPercent int   `json:"used_percent"`
	ResetAt     int64 `json:"reset_at"` // Unix timestamp
}

// CodexJWTClaims decoded from id_token
type CodexJWTClaims struct {
	Email    string `json:"email"`
	PlanType string `json:"chatgpt_plan_type,omitempty"`
}

func fetchCodexUsage(client *http.Client, accessToken string, accountID string) (CodexAccountQuota, error) {
	req, err := http.NewRequest("GET", codexUsageAPI, nil)
	if err != nil {
		return CodexAccountQuota{}, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")
	if accountID != "" {
		req.Header.Set("Chatgpt-Account-Id", accountID)
	}

	resp, err := client.Do(req)
	if err != nil {
		return CodexAccountQuota{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return CodexAccountQuota{}, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	var usageResp CodexUsageAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&usageResp); err != nil {
		return CodexAccountQuota{}, err
	}

	quota := CodexAccountQuota{
		PlanType: usageResp.PlanType,
	}

	if usageResp.RateLimit != nil {
		quota.LimitReached = usageResp.RateLimit.LimitReached

		// Primary window = session (5h)
		if usageResp.RateLimit.PrimaryWindow != nil {
			quota.SessionPercent = float64(100 - usageResp.RateLimit.PrimaryWindow.UsedPercent)
			if usageResp.RateLimit.PrimaryWindow.ResetAt > 0 {
				resetTime := time.Unix(usageResp.RateLimit.PrimaryWindow.ResetAt, 0)
				quota.SessionResetIn = formatResetTimeFromTime(resetTime)
			}
		}

		// Secondary window = weekly
		if usageResp.RateLimit.SecondaryWindow != nil {
			quota.WeeklyPercent = float64(100 - usageResp.RateLimit.SecondaryWindow.UsedPercent)
			if usageResp.RateLimit.SecondaryWindow.ResetAt > 0 {
				resetTime := time.Unix(usageResp.RateLimit.SecondaryWindow.ResetAt, 0)
				quota.WeeklyResetIn = formatResetTimeFromTime(resetTime)
			}
		}
	}

	return quota, nil
}

func formatResetTimeFromTime(t time.Time) string {
	now := time.Now()
	diff := t.Sub(now)

	if diff <= 0 {
		return "now"
	}

	hours := int(diff.Hours())
	minutes := int(diff.Minutes()) % 60
	days := hours / 24
	hours = hours % 24

	if days > 0 {
		if hours > 0 {
			return fmt.Sprintf("%dd %dh", days, hours)
		}
		return fmt.Sprintf("%dd", days)
	}
	if hours > 0 {
		if minutes > 0 {
			return fmt.Sprintf("%dh %dm", hours, minutes)
		}
		return fmt.Sprintf("%dh", hours)
	}
	return fmt.Sprintf("%dm", maxInt(1, minutes))
}

func isCodexTokenExpired(accessToken string) bool {
	parts := strings.Split(accessToken, ".")
	if len(parts) < 2 {
		return true
	}

	// Decode payload (second part)
	payload := parts[1]
	// Add padding
	switch len(payload) % 4 {
	case 2:
		payload += "=="
	case 3:
		payload += "="
	}
	// Replace URL-safe chars
	payload = strings.ReplaceAll(payload, "-", "+")
	payload = strings.ReplaceAll(payload, "_", "/")

	data, err := base64.StdEncoding.DecodeString(payload)
	if err != nil {
		return true
	}

	var claims map[string]interface{}
	if err := json.Unmarshal(data, &claims); err != nil {
		return true
	}

	exp, ok := claims["exp"].(float64)
	if !ok {
		return true
	}

	// Token is expired if exp is in the past (with 60s buffer)
	return time.Unix(int64(exp), 0).Before(time.Now().Add(60 * time.Second))
}

func refreshCodexToken(client *http.Client, refreshToken string) (string, error) {
	payload := map[string]string{
		"grant_type":    "refresh_token",
		"refresh_token": refreshToken,
		"client_id":     codexClientID,
	}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequest("POST", codexTokenURL, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("token refresh failed: HTTP %d", resp.StatusCode)
	}

	var tokenResp struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return "", err
	}

	return tokenResp.AccessToken, nil
}

func decodeCodexJWT(token string) *CodexJWTClaims {
	parts := strings.Split(token, ".")
	if len(parts) < 2 {
		return nil
	}

	payload := parts[1]
	switch len(payload) % 4 {
	case 2:
		payload += "=="
	case 3:
		payload += "="
	}
	payload = strings.ReplaceAll(payload, "-", "+")
	payload = strings.ReplaceAll(payload, "_", "/")

	data, err := base64.StdEncoding.DecodeString(payload)
	if err != nil {
		return nil
	}

	var rawClaims map[string]interface{}
	if err := json.Unmarshal(data, &rawClaims); err != nil {
		return nil
	}

	claims := &CodexJWTClaims{}
	if email, ok := rawClaims["email"].(string); ok {
		claims.Email = email
	}

	// Extract plan from nested auth object
	if auth, ok := rawClaims["https://api.openai.com/auth"].(map[string]interface{}); ok {
		if planType, ok := auth["chatgpt_plan_type"].(string); ok {
			claims.PlanType = planType
		}
	}

	return claims
}
