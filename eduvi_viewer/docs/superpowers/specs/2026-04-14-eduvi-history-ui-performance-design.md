# EduVi Viewer History, UI, and Performance Design

## Context
User requested:
- Beautify the desktop app UI.
- Optimize app performance.
- Provide detailed open-history view grouped by metadata inside `.eduvi` files.
- Grouping keys are:
  - `projectCode`, `projectName`
  - `subjectCode`, `subjectName`
  - `gradeCode`, `gradeName`
- Keep up to 200 history records.

## Goals
1. Improve overall visual quality of Home and History experiences.
2. Persist and display detailed history grouped by grade -> subject -> project.
3. Add practical filters and search for fast exploration.
4. Improve responsiveness when opening larger `.eduvi` files.

## Non-Goals
1. Replace presentation rendering architecture entirely.
2. Introduce external database migration for now.
3. Change EDUVI schema itself.

## Chosen Approach
Balanced approach (option 2):
- SharedPreferences-backed history list with capped size (200).
- New structured history model with analytics fields.
- New dedicated History screen with grouped expandable UI and filters.
- Performance improvements in file parsing and rendering hotspots.

## Data Model Design
### History entry
Each open action stores one immutable event with:
- identity: `id`
- source: `filePath`
- timestamps: `openedAt`, `sourceUpdatedAt`
- presentation meta: `title`, `description`, `createdAt`
- grouping meta: grade, subject, project code/name pairs
- analytics: `slideCount`, `blockTypeCounts`, `hasVideo`, `hasQuiz`

### Persistence
- Keep legacy key for backward compatibility (`last_opened_eduvi`).
- Store history list under a new key (`eduvi_open_history_v2`).
- Trim history to latest 200 entries after each save.
- Migrate legacy single-entry to new list when needed.

## UI/UX Design
### Home Screen
- Keep drag-and-drop primary flow.
- Improve visual hierarchy and spacing.
- Add clear action to open History screen.
- Preserve last-opened quick card with richer metadata display.

### History Screen
- Add list grouped by:
  1. Grade (`gradeCode` + `gradeName`)
  2. Subject (`subjectCode` + `subjectName`)
  3. Project (`projectCode` + `projectName`)
- Add search and filters:
  - grade
  - subject
  - project
  - hasVideo toggle
  - hasQuiz toggle
- Per-item details:
  - title
  - opened timestamp
  - source update timestamp
  - slide count
  - block type chips
  - path summary
- Actions:
  - reopen file
  - remove item
  - clear history

## Data Flow
1. User opens `.eduvi` file.
2. App parses schema.
3. App computes history analytics from schema cards/layouts/blocks.
4. App writes history event and trims list.
5. History screen reads entries, applies filters, groups entries, renders nested sections.

## Error Handling
1. Missing metadata: fallback to `Unknown` labels.
2. Missing file path on reopen: show non-blocking error snackbar.
3. Corrupt history payload item: skip invalid item, keep remaining entries.
4. Parse failure: preserve current UX error reporting.

## Performance Plan
1. Parse JSON using isolate (`compute`) to reduce UI jank.
2. Avoid unnecessary full widget rebuilds in history filtering path.
3. Keep rendering list lazy and grouped only after filtering.
4. Keep memory footprint bounded via 200-entry cap.

## Testing Strategy
1. Unit tests for history service:
  - save event
  - migration from legacy key
  - trim to 200 entries
  - analytics extraction correctness
2. Widget tests for history UI:
  - grouped rendering
  - filtering/search behavior
  - empty state behavior

## Risks and Mitigations
1. Risk: SharedPreferences payload grows with analytics fields.
  - Mitigation: hard cap 200, compact JSON fields.
2. Risk: Grouping complexity hurts readability.
  - Mitigation: nested expandable sections with concise headers and counts.
3. Risk: Backward compatibility issues.
  - Mitigation: keep and read legacy key, migrate lazily.

## Acceptance Criteria
1. App stores up to 200 history events.
2. History is grouped by grade -> subject -> project from EDUVI metadata.
3. User can search and filter history effectively.
4. Home screen includes direct entry point to history.
5. Opening `.eduvi` remains responsive and stable.
6. Existing open/view workflow remains functional.
