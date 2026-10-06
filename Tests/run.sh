#!/bin/zsh
# Compiles the model, the scheduler, the queue and the store on their own and
# runs the checks in main.swift. None of them needs SwiftUI, a window or a
# running application.
set -e
cd "$(dirname "$0")"

swiftc -swift-version 6 -default-isolation MainActor -O \
  ../Words/Model/*.swift \
  ../Words/Scheduling/*.swift \
  ../Words/Persistence/*.swift \
  ../Words/Anki/*.swift \
  ../Words/DesignSystem/DueText.swift \
  ../Words/Features/Study/StudySession.swift \
  ../Words/Features/Library/WordRow.swift ../Words/DesignSystem/Palette.swift \
  SchedulerChecks.swift QueueChecks.swift PromptChecks.swift AssistantChecks.swift PracticeOptionChecks.swift StreakChecks.swift LimitChecks.swift LibraryChecks.swift \
  DeckChecks.swift InsightsChecks.swift ActivityLayoutChecks.swift ImportChecks.swift PracticeChecks.swift \
  SessionChecks.swift EndlessChecks.swift AudioChecks.swift AssociationChecks.swift AnkiChecks.swift GameChecks.swift \
  PersistenceChecks.swift StoreChecks.swift main.swift \
  -o /tmp/words-modelchecks

/tmp/words-modelchecks
