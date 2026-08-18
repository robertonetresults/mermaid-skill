# 工作流程与文件结构

[← 返回 README](../README_CN.md)

## 工作原理

每个生成的源码都必须校验，导出则必须由用户明确要求。

![仅本地校验工作流](../assets/workflow_cn.png)

```mermaid
flowchart LR
  Start([用户请求图表]) --> Generate[生成 .mmd 源码]
  Generate --> Local{本地 mmdc 可用?}
  Local -->|是| Validate[使用临时 SVG 校验]
  Local -->|否| Container{本地 CLI 容器可用?}
  Container -->|是| Validate
  Container -->|否| Kroki{回环 Kroki 可用?}
  Kroki -->|是| Validate
  Kroki -->|否| Unvalidated([报告源码未校验])
  Validate --> Result{语法有效?}
  Result -->|否| Fix[修复 .mmd 源码]
  Fix --> Validate
  Result -->|是| Export{明确要求格式?}
  Export -->|否| Source([报告已校验 .mmd])
  Export -->|是| Render[仅导出指定格式]
  Render --> Report([报告输出路径])
```

用于校验的临时 SVG 会自动删除。只有用户明确指定格式时才创建持久化 PNG、SVG 或 PDF。

## 技能结构

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
