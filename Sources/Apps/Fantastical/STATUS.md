# Fantastical

- Bundle id: com.flexibits.fantastical2.mac
- Support: Partial
- Effort: Module
- Being worked on: Unclaimed
- Checked: 13 November 2026; Fantastical 4.2.4, macOS 27.2.1, developer build from main at 6233242; Windows keyboard style, TurnOver reading alone.

## Findings

Before the module, the month view read as one run of events with no days between them, an event's popover could not be reached, and the new event field's suggestions were never said.

With the module, tried with the key driver (`turnover-plugin try`) and by ear: the month, quarter, week and day views read by day and by event; an event opens into its popover, where Tab moves between its controls and the date and time controls say the date or the time; the new event field says its suggestions, what Fantastical has understood, and what was added. In Go to Date (Shift Command T) the date field says which part (day, month, year) Tab or an arrow has moved to, and each change once (13 Nov 2026). The module's opening comment says what Fantastical reports and what each key does.

Return on an event (13 Nov 2026): the month grid draws only the events that fit in a day's box, and a press on one of the others selects it and opens nothing. Return is now Fantastical's own: TurnOver puts the keyboard on the view, presses the event, and sends Return on, and Fantastical opens the selected event's details with the keyboard in their title, drawn or not. Tried with the key driver on drawn, undrawn and all-day events in the month view, on events in the week view, and in the day view, where the details stand beside the day and not in a popover. The route by way of the day view, tried the same day, never worked and is gone. [The measurements](Experiments/2026-11-13-opening-events.md).

Known gaps: the year view, tasks and the task list, the mini window, notifications (Shift Command N) beyond Tab through an invitation's buttons, and the sidebar's event list, which TurnOver reads as a plain table. Delete on an event beyond the ones a day's box shows has only been reasoned through: the key driver cannot press Delete. In the quarter view, where the weeks are too small for Fantastical to draw an event's title (53 points a week in a window 859 points high), no event opens: Fantastical has no place to show the details from, and TurnOver says that it could not open the event. In the day view an event is said without its times, as Fantastical words it there, and Option Up and Down have not been tried there. Return's new way has been tried with the key driver against Fantastical itself, not yet by ear in the installed build. Fantastical in a language other than English falls back to its own whole sentences. The Mac keyboard style and VoiceOver's keys are untried.

## Evidence

[App implementation](FantasticalAppModule.swift).

[How to check it by hand](Tests/README.md).
