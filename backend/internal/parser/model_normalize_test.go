package parser

import "testing"

func TestNormalizeModel(t *testing.T) {
	cases := map[string]string{
		"claude-sonnet-4-5-20251015":     "claude-sonnet-4-5",
		"claude-sonnet-4-20250514":       "claude-sonnet-4",
		"claude-opus-4-7-20260301":       "claude-opus-4-7",
		"claude-haiku-4-5-20250901":      "claude-haiku-4-5",
		"claude-opus-4-7":                "claude-opus-4-7", // already canonical
		"gpt-5.2-codex":                  "gpt-5.2-codex",
		"gpt-5.2-codex-20251223":         "gpt-5.2-codex",
		"gpt-5.4-codex-20260301":         "gpt-5.4-codex",
		"gpt-5.4":                        "gpt-5.4-codex", // bare CLI form normalizes to pricing key
		"unknown-model-xyz":              "unknown-model-xyz", // pass-through
		"":                               "",
	}
	for in, want := range cases {
		got := NormalizeModel(in)
		if got != want {
			t.Errorf("NormalizeModel(%q) = %q; want %q", in, got, want)
		}
	}
}
