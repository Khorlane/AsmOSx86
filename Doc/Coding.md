# 📐 Coding Standards (AsmOSx86)

AsmOSx86 favors **clarity, consistency, and mechanical readability**
over brevity or cleverness.

These rules are enforced across the entire codebase.

---

## 1. Assembly Formatting Rules (MANDATORY)

### 1.1 Column Alignment

| Element | Column |
|------|--------|
| Instruction mnemonic | Column 3 |
| Operand 1 | Column 9 |
| Operand separator | No spaces around commas |
| Line comments | Column 41 |

### Example
```
         1         2         3         4
12345678901234567890123456789012345678901
  mov   eax,TimerTicksLo                ; Load low tick count
```

---

## 2. Commenting Rules

### File Headers
- Every file starts with a **full-width banner**
- Must describe purpose, scope, and contracts

### Section Headers
- Use dashed separators
- Describe intent, not mechanics

### Inline Comments
- Explain *why*, not *what*
- Avoid restating the instruction

---

## 3. Naming Conventions

### General Principles
- Prefer full words
- Abbreviations must be consistent everywhere
- Do not mix abbreviated and full forms

### Common Abbreviations
| Abbrev | Meaning |
|------|--------|
| Addr | Address |
| Attr | Attribute |
| Char | Character |
| Col | Column |
| Desc | Descriptor |
| Fore | Foreground |
| Hex | Hexadecimal |
| Ofs | Offset |
| Str | String |
| Sz | Size |
| Vid | Video |
| Xlate | Translate |

---

## 4. Prefix Usage

### Subsystem Prefixes
Used when ownership is clear:
- `Cn*` → Console
- `Kb*` → Keyboard
- `Flp*` → Floppy
- `Timer*` → Timer
- `Time*` → Wall time
- `Uptime*` → Uptime
- `Vid*` → Video

### Kernel-Wide Primitives
- May be unprefixed if globally applicable

---

## 5. Register Discipline

- Preserve registers unless explicitly documented otherwise
- `pusha` / `popa` used consistently for public routines
- Stage return values if `popa` would clobber them

---

## 6. Contracts Over Assumptions

- Each module documents:
  - What it exports
  - What it requires
- The kernel must respect call ordering when stated
- Hidden coupling is forbidden

---

## 7. Design Philosophy

- **Explicit beats implicit**
- **Localize complexity**
- **One owner per responsibility**
- **Monotonic time is sacred**

---

## 8. Stability Rule

Once a behavior is marked **LOCKED-IN**:
- It may not change without deliberate refactoring
- Callers may rely on it permanently

---

**This document defines the canonical coding standard for AsmOSx86.**