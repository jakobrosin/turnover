# Fantastical

- Bundle id: com.flexibits.fantastical2.mac
- Support: Partial
- Effort: Module
- Being worked on: Unclaimed
- Checked: 12 November 2026; Fantastical 4.2.4, macOS 27.2, developer build from main at 6233242; Windows keyboard style, TurnOver reading alone.

## Findings

Before the module, the month view read as one run of events with no days between them, an event's popover could not be reached, and the new event field's suggestions were never said.

With the module, tried with the key driver (`turnover-plugin try`) and by ear: the month, quarter, week and day views read by day and by event; an event opens into its popover, where Tab moves between its controls and the date and time controls say the date or the time; the new event field says its suggestions, what Fantastical has understood, and what was added. The module's opening comment says what Fantastical reports and what each key does.

Known gaps: the year view, notifications (Shift Command N; none were there to look at), tasks and the task list, the mini window, and Delete, which the key driver cannot press and has only been reasoned through. Fantastical in a language other than English falls back to its own whole sentences. The Mac keyboard style and VoiceOver's keys are untried.

## Evidence

[App implementation](FantasticalAppModule.swift).

[How to check it by hand](Tests/README.md).
