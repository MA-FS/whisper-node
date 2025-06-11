#!/bin/bash

# Claude Code MCP Server Setup Script
# This script configures all dockerized MCP servers for Claude Code CLI

echo "🚀 Setting up all MCP servers for Claude Code CLI..."

# Clean up any existing configurations to avoid conflicts
echo "🧹 Cleaning up old configurations..."

# Check if claude command is available
if ! command -v claude &> /dev/null; then
    echo "❌ Claude Code CLI not found. Please install it first:"
    echo "   npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Check if Docker containers are running
echo "📦 Checking Docker containers..."
if ! docker-compose ps | grep -q "Up"; then
    echo "⚠️  Starting Docker containers..."
    docker-compose up -d
    sleep 5
fi

echo "🔧 Configuring MCP servers..."

# Remove any existing configurations to avoid conflicts
echo "   Removing existing configurations..."
claude mcp remove context7 2>/dev/null || true
claude mcp remove sequential-thinking 2>/dev/null || true
claude mcp remove desktop-commander 2>/dev/null || true
claude mcp remove memory 2>/dev/null || true
claude mcp remove supabase 2>/dev/null || true
claude mcp remove notion 2>/dev/null || true
claude mcp remove playwright 2>/dev/null || true

# Add all MCP servers
echo "   Adding MCP servers..."

echo "     📚 Context7..."
claude mcp add-json context7 '{"command": "docker", "args": ["exec", "-i", "mcp-context7", "npx", "@upstash/context7-mcp"], "env": {}}'

echo "     🧠 Sequential Thinking..."
claude mcp add-json sequential-thinking '{"command": "docker", "args": ["exec", "-i", "mcp-sequential-thinking", "npx", "@modelcontextprotocol/server-sequential-thinking"], "env": {}}'

echo "     💻 Desktop Commander..."
claude mcp add-json desktop-commander '{"command": "docker", "args": ["exec", "-i", "mcp-desktop-commander", "npx", "@wonderwhy-er/desktop-commander"], "env": {}}'

echo "     🧮 Memory..."
claude mcp add-json memory '{"command": "docker", "args": ["exec", "-i", "mcp-memory", "npx", "@modelcontextprotocol/server-memory"], "env": {"MEMORY_FILE_PATH": "/data/memory.json"}}'

echo "     🗄️  Supabase..."
claude mcp add-json supabase '{"command": "docker", "args": ["exec", "-i", "mcp-supabase", "npx", "@supabase/mcp-server-supabase"], "env": {}}'

echo "     📝 Notion..."
claude mcp add-json notion '{"command": "docker", "args": ["exec", "-i", "mcp-notion", "npx", "@notionhq/notion-mcp-server"], "env": {}}'

echo "     🎭 Playwright..."
claude mcp add-json playwright '{"command": "docker", "args": ["exec", "-i", "mcp-playwright", "npx", "@executeautomation/playwright-mcp-server"], "env": {}}'


echo ""
echo "✅ All MCP servers configured!"
echo ""
echo "📊 Current MCP server status:"
claude mcp list
echo ""
echo "🔍 To verify connections, you can test with:"
echo "   claude --print 'List available MCP tools'"
echo ""
echo "🎉 Setup complete! All 7 MCP servers are ready to use."