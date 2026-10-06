# Data and analytics contract

## AnswerRecord (Codable, Sendable, Identifiable)

| Field | Meaning |
|---|---|
| `id` | Unique event UUID; use as a database idempotency key |
| `runID` | One level attempt; changes on Retry or Next level |
| `challengeID` | One presentation of a card; shared by its retries |
| `timestamp` | Wall-clock event date |
| `scopeID`, `mode`, `level` | Learning context, actual question direction and current level |
| `studyMode` | Selected run mode, including mixed; nil on old records means mode |
| `cardID`, `categoryIDs` | Original host identifiers at answer time |
| `word`, `translation` | Original card text, independent of direction |
| `prompt`, `correctAnswer`, `selectedAnswer` | Actual presented question and selected response |
| `isCorrect` | Whether the selected zone was correct |
| `attempt` | 1 for first crossing; 2+ for retries of the same question |
| `responseTime` | Seconds from question presentation, or previous mistake, excluding pause; retry timing includes rebound |
| `points` | Points earned on this crossing, including multiplier; 0 on mistakes |

Events report recognition in a multiple-choice game. They do not assign Anki/FSRS grades. The host must choose how this evidence affects its learning model. A correct second attempt should not be treated as a correct first recall.

## ProgressSnapshot (schemaVersion 1)

- `words`: keyed by host card ID. Stores last seen text/categories and separate direction statistics.
- `levels`: keyed by encoded scope/mode/level. Stores completed/failed run counts, wins, best score and last played time.
- `earnedPoints`: all correct-answer points, including retries and unfinished runs. This is not a sum of best scores.
- `answerIDs` and `completedRunIDs`: deduplication sets; retained for the profile lifetime. Raw event history is not stored here. Persist callbacks in the host if it needs session timelines or daily charts.
- `revision`: monotonically increases on newly ingested events/results; local write ordering only.

`WordStatistics` exposes total attempts, mistakes, first attempts, first-try correct and first-try accuracy. Each `DirectionStatistics` additionally exposes total response time, average response seconds, last-practiced date and counts of incorrectly selected answer text. Average response time includes successful and failed attempts. Repeated cards count as new first attempts when presented as a new question.

Example: incorrect first attempt followed by a correct retry means **2 attempts, 1 mistake, 0/1 first-try correct**. The retry earns points but does not erase the mistake. The dashboard sorts words by total mistakes; expand a word to inspect directions and confusions.

Unlocked level is the highest completed level plus one, independently per scope and mode. Failed and abandoned runs do not unlock levels. A custom host may allow any starting level; the standard library only lets the user select unlocked levels. The completed-level total sums successful runs, including successful replays.

Statistics survive word edits because IDs are stable. Deleting a word from the supplied deck does not delete its historical statistics. Renaming a category does not reset levels; changing its ID creates a new context. Decide retention/deletion rules in the host.

The main menu's Correct percentage is `totalCorrectAnswers / totalAttempts`; retries count in both totals. Detailed first-try accuracy remains a separate metric. `totalCompletedLevels` sums all level completion counts, and earnedPoints is the lifetime total.

## Storage and scale

JSON is intended for a local learner profile. Aggregate dictionaries and deduplication IDs grow with learning history. For large deployments or cross-device sync, implement `ProgressStorage` using your repository, retain raw event IDs there, and establish your own compaction/migration policy. No per-frame persistence is performed; snapshots are queued only on answer or level-result events.

Only schema 1 is accepted by the built-in loader. Future versions should use explicit migrations rather than discarding fields or resetting profiles. Codable dates use Foundation's default encoding (seconds relative to 2001-01-01); host exports may choose a different date strategy if the matching decoder uses it.
