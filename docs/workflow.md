# Workflow & File Structure

[← Back to README](../README.md)

## How It Works

Every generated source is validated. Export remains an explicit opt-in.

![Local-only validation workflow](../assets/workflow.png)

```mermaid
flowchart LR
  Start([User requests diagram]) --> Generate[Generate .mmd source]
  Generate --> Local{Local mmdc works?}
  Local -->|Yes| Validate[Validate with temporary SVG]
  Local -->|No| Container{Local CLI container works?}
  Container -->|Yes| Validate
  Container -->|No| Kroki{Loopback Kroki works?}
  Kroki -->|Yes| Validate
  Kroki -->|No| Unvalidated([Report source as not validated])
  Validate --> Result{Syntax valid?}
  Result -->|No| Fix[Fix .mmd source]
  Fix --> Validate
  Result -->|Yes| Export{Format explicitly requested?}
  Export -->|No| Source([Report validated .mmd])
  Export -->|Yes| Render[Export requested formats only]
  Render --> Report([Report output paths])
```

The temporary validation SVG is deleted automatically. Persistent PNG, SVG, and PDF files are created only when the user explicitly requests those formats.

## Skill Structure

```text
skills/mermaid-skill/
├── SKILL.md
├── scripts/
│   └── render-mermaid.sh
└── reference/
    ├── LOCAL-RENDERING.md
    ├── FLOWCHART.md
    ├── SEQUENCE.md
    ├── CLASS-ER.md
    └── OTHER-TYPES.md
```
