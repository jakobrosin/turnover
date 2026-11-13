# Fantastical: opening an event the month grid has not drawn, 13 November 2026

- Being worked on: Unclaimed
- Contributors and tools: Jakob Rosin, by ear; Claude Code (Claude Fable 5.2) probed the running app through the accessibility interface with small scratch tools, drove keys with `turnover-plugin try`, and read Fantastical's program files for the reason behind what was seen.
- Date and setup: 13 November 2026; Fantastical 4.2.4 in English, macOS 27.2.1, developer build from main at 6233242 with the Fantastical module, Windows keyboard style, TurnOver reading alone. The calendar was a real one, so nothing of it is kept here: counts, places on screen and structure only.
- Review point: after some days of daily use, with the rest of the module.
- Status: Graduated into the module (Return and Delete on an event); the sidebar's event list is recorded and not used.

## Question

In the month view, Return opened the first three events of a day and none of the others. A first answer, opening such an event by switching to the day view, never worked in the installed app. Is there a way to open, and to delete, any event of a day that does not depend on what the grid has drawn, without switching views and without the mouse?

## Method

A day with seven events in a box 118 points high, in a window 859 points high showing six weeks. Each step was one accessibility call or one key, with the state read back after it: which popovers exist and what their title field holds, which windows Fantastical has, what it names as its focused element, and which row its sidebar list has selected. Keys went through `turnover-plugin try`, so they passed TurnOver as a person's keys do. Nothing was deleted and nothing was typed into a field.

## Result

Observed:

- A day's box draws the events that fit and a line "4 more…" in the last place. Every event of the day is in the accessibility tree all the same, with a frame, a press action and a menu action; the frames of the undrawn ones run on below the box, over the next week's row. The "more" line is not in the tree. The system hit test finds it, as a static text with no actions.
- A press on a drawn event opens its popover and returns an error code (minus 25200). A press on an undrawn event returns success, opens nothing, and makes the event Fantastical's selected one: the sidebar's list, when shown, has its row selected at once. Seven events, pressed one after another from a clean state: the first three opened, the last four did not.
- With an event selected and nothing open, Command I (Edit, Get Info) opens that event's popover, undrawn or not, and leaves the keyboard where it was. It closes a popover that is open.
- With the keyboard on the view (the "Month view" scroll area takes it when its AXFocused attribute is set) and an event selected, Return opens the event's popover if it is not open and puts the keyboard in its title field. With the popover already open, as after a press on a drawn event, Return puts the keyboard in the title field and closes nothing. Escape then closes the popover and the keyboard is back on the view. Tried on an undrawn timed event, a drawn timed event and a drawn all-day event in the month view, and on a timed and an all-day event in the week view, where the "timed events" area takes the keyboard the same way.
- In the day view a pressed event's details are not a popover: a scroll area described "Event details" appears beside the day, in the window itself, and goes when nothing is selected. Return puts the keyboard in its title field; Escape takes the details away and leaves the keyboard on the window.
- In the quarter view of the same window a week is 53 points high and Fantastical draws no event's title and no "more" line (the hit test finds only the week). There a press selects nothing that can be shown: Return and Command I both opened nothing for the day's last event. Fantastical has no place to show the details from.
- After another app has been in front, Fantastical names no focused element at all. In that state a popover opened by a press stayed open under one Escape after another. A press on the day's own element closed it, every time it was tried, and cleared the selection.
- Selecting an undrawn event from outside the grid (its row in the sidebar's list, by AXSelectedRows) makes the grid open the day's box over itself: a window of subrole AXUnknown, 155 points wide, holding the whole week again with that day's events all drawn. While it is open the grid's own elements for that day all take a press. It stays open while the selection stays.
- The sidebar (Option Command S; hidden in every earlier look at this app) adds a group described "sidebar": a small month with a button a day, and a table described "Event list" of 523 rows covering about two months either side. A day has a heading row, one row for all its all-day events together, and a row a timed event, with the title, the place and the times as separate texts and a custom action named Delete. Each day's button and that day's heading row name each other in AXLinkedUIElements. A day with nothing to show has no heading, and its button names the heading of the day before. The rows are renumbered as the list is read on (today's heading was row 233, later 231).
- With the keyboard in that table, Fantastical's own Down and Up move the selection, passing the headings, and show the selected event's popover each time; Return puts the keyboard in the popover's title, Space shows the popover without moving it, Escape closes it. Down steps through the all-day events inside their one row; Up comes into the row at its last event and leaves it at the next press. TurnOver read each row as a table row ("title, times, 240 of 523") and read the whole all-day row at every step inside it.
- Fantastical's own Tab in an open popover went title, emoji button, location, all-day checkbox, time zone, calendar, category, alert, show as, and out: it passes the four date and time controls by.

Explanation, from reading the program (Fantastical 4.2.4, arm64), not observed directly:

- The press handler selects the item first and then asks for the selected item's view; for an undrawn item the "more" label is handed back in its place, the handler finds it is not an item view, and returns without presenting anything. That is why the selection is made and nothing opens.
- Fantastical switches a set of behaviours on only while VoiceOver itself is running (it asks the system whether VoiceOver is enabled): an event becomes selected when it is given the accessibility focus, and a day's box is never opened over the grid. TurnOver keeps VoiceOver off, so it gets the behaviour meant for sighted use. Setting AXFocused on an event did nothing on 12 November for this reason.
- Control with an arrow moves the selected event to another day or time. TurnOver's own keys in the view never send an arrow on, and nothing in the module sends one with Control.

What did not work:

- Opening the event in the day view after switching to it: the day view words an event without its times, so the search for the same words never found it, and had it been found, the day view opens no popover to go into. Three attempts in the installed app, three failures, each 2.3 seconds of silence.
- Judging by frames which events are drawn: the last line that fits is the "more" line, and on one day the events are not listed in their order on screen.
- Choosing Get Info from the menu bar by an accessibility press while Fantastical named no focused element: the item read as disabled and the press did nothing. The key, Command I, worked in the same state.
- A press on an event inside the day's opened box: success returned, nothing opened. The grid's own element for the same event did open.

Untested: Delete, which the key driver refuses to press; it is reasoned from the same selection and has to be tried by hand. The new module code itself in the installed app: the keys above were sent to Fantastical with the old module out of the way. The year view, and a quarter view tall enough to draw titles. Fantastical in another language. The Mac keyboard style.

## Evidence

[The module](../FantasticalAppModule.swift): `openEvent`, `confirmOpened`, `holdKeyboard`, `deleteEvent`, `leavePopover`. [Hand checks](../Tests/README.md), 9 to 12. The scratch tools and recordings hold private calendar text and were not kept.

## What would justify another attempt

- Reading events from the sidebar's list instead of the grid. It is the one place where Fantastical's own keys do everything (move, open, close, delete) on a selection that is the reading, and it is the same in every view. Against it: the sidebar has to be showing, which widens the window by 300 points; all-day events share a row and Up does not step through them; the rows carry no calendar name; and the module's days, wording and place in the view would all be rebuilt on it. Worth a design note and the user's say before any code.
- A Fantastical that offers its VoiceOver behaviour to any assistive app, or a press that presents an undrawn event: either would make the selecting press enough by itself.

## Decision

Graduate: Return on an event is the keyboard put on the view, the event pressed, and Return sent on; Delete checks the selection by the details' title, with Get Info to show them for an undrawn event. The day-view route and the frame arithmetic are removed.
