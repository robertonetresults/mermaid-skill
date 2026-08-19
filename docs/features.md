# Features & Comparison

[← Back to README](../README.md)

## Why This Skill?

| Feature | This Skill | Native Claude Code | Other Skills | MCP Server |
| --------- | ----------- | ------------------- | -------------- | ------------ |
| **Write Mermaid syntax** | Guided by examples | Built-in capability | Varies | Varies |
| **Source validation** | Always required, with fix/re-validate | No validation loop | Often skipped | Varies |
| **Export to PNG/SVG/PDF** | Explicit opt-in | Manual — user must ask | Usually one method | Often web-only |
| **Local fallback chain** | Local CLI → local container → loopback Kroki | No fallback | Requires setup | Varies |
| **Proactive triggering** | Auto-triggers for 3+ components | Only when explicitly asked | Manual only | Manual |
| **End-to-end workflow** | Generate → Validate → optional export → Report | Generate only | Partial | Partial |
| **Progressive disclosure** | Syntax in separate files | N/A | All inline | N/A |

**Key advantages over native Claude Code:**

- **Always-valid source** — validation and error recovery run even when no image was requested
- **No implicit export** — persistent PNG/SVG/PDF output is created only for explicitly named formats
- **Local-only backends** — local `mmdc`, a network-isolated local CLI container, then loopback Kroki
- **Proactive diagramming** — auto-triggers when discussing architecture, not just when you ask for a diagram

## What This Skill Can Do

### Diagram Types (17+)

| Type | Use for | Example |
| ------ | --------- | --------- |
| **Flowchart** | Processes, pipelines, decision trees | CI/CD pipeline, user registration flow |
| **Sequence** | API calls, authentication flows | JWT auth, microservice communication |
| **Class** | OOP models, data structures | Domain models, inheritance hierarchies |
| **ER** | Database schemas | User-Order-Product relationships |
| **State** | State machines, lifecycles | Order status, connection states |
| **Gantt** | Project timelines | Sprint planning, release schedules |
| **Pie** | Proportions, distributions | Market share, resource allocation |
| **Git Graph** | Branch strategies | GitFlow, trunk-based development |
| **C4 Context** | High-level architecture | System context, container diagrams |
| **Mind Map** | Topic breakdowns | Feature planning, brainstorming |
| **Use Case** | Actor–system interactions (UML) | Login flow, role permissions |
| **Cynefin** | Sense-making / complexity domains | Incident response, strategy |
| **Event Modeling** | Event-driven system timelines | Cart add-to-order flow |
| **Tree View** | File / directory hierarchies | Project structure docs |
| **Wardley Maps** | Business strategy / value chains | Build vs. buy analysis |

### Output Formats

Output formats are opt-in. Without an explicit format request, the skill returns only the validated `.mmd` source.

- **PNG** — High resolution (2048px), white background, multiple themes
- **SVG** — Scalable vector, perfect for docs
- **PDF** — Print-ready documents

### Automatic Triggering

The skill activates when you:

- Ask for diagrams explicitly: *"create a flowchart"*, *"draw architecture"*
- Explain complex systems: *"how does authentication work"* (3+ components)
