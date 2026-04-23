package parser

// List returns all built-in tool parsers. Add new tools here (OCP extension point).
func List() []ToolParser {
	return []ToolParser{NewClaudeParser(), NewCodexParser()}
}
