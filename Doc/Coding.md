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

### Label Naming Standard

All labels local to a routine must be named using the following pattern:

**RoutineName + SequentialNumber (starting at 1)**

- This ensures clarity, uniqueness, and logical flow within the routine.
- Labels should never be generic (e.g., `loop`, `done`, `retry`), but always tied to their parent routine.
- The numbering should reflect the order of appearance or logical steps in the routine.
- If additional clarity is needed, a short descriptive suffix may be appended (e.g., `TimerDelayMs2_Compare`).

**Example:**
```
TimerDelayMs1:
  ; First step after entry

TimerDelayMs2:
  ; Main polling loop

TimerDelayMs3:
  ; Exit/return point
```

This standard prevents naming collisions, improves code navigation, and makes control flow explicit.

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