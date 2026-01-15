// Package web provides embedded web assets for the dashboard.
package web

import "embed"

//go:embed templates/* static/js/* static/images/*
var Assets embed.FS
