# Fantastical: first look and what was tried, 12 November 2026

- Being worked on: Unclaimed
- Contributors and tools: Jakob Rosin, by ear; Claude Code (Claude Fable 5.2) wrote the module and drove the keys with `turnover-plugin snapshot`, `menus` and `try`.
- Date and setup: 12 November 2026; Fantastical 4.2.4 in English, macOS 27.2, developer build from main at 6233242, Windows keyboard style, TurnOver reading alone. The calendar was a real one, so nothing of it is kept here.
- Review point: after some days of daily use.
- Status: Graduated into the module; the gaps below are open.

## Question

Fantastical's month view read as one run of events. Can a module give it days, events, an event's details and the new event field, from what Fantastical reports to accessibility?

## Method

Snapshots of each view and popover, then keys through `turnover-plugin try`, comparing what TurnOver said before and after each change. The user tried each build by ear. Events made for the trial were named "claude test" and "claude invite"; one invitation went to the user's own second address.

## Result

What Fantastical reports, as observed:

- Month and quarter views: a scroll area ("Month view", "Quarter view"), a group a week, a group a day described with its date and count, the events as pressable static texts. All report themselves disabled.
- Week and day views: three scroll areas, "days", "all day events" and "timed events". The keyboard never reaches the events.
- An event's popover hangs under the week's group in the month view. The keyboard stays on the view behind it.
- The new event field (Command N) is a text area, identifier ParserInputTextView, in a popover with the event's details under it. Its suggestions are a table in a window of their own.
- Notifications (Shift Command N): a popover headed "Notifications" with a table; Tab skips the Accept button.
- The mini window belongs to the helper process, a login item inside Fantastical, with the same sentence field.

What did not work, and why it is not in the module:

- Setting an event's AXFocused attribute to make it Fantastical's selection: the call succeeds and Delete still acts on the event last clicked. Pressing the event does select it, so Delete presses it first.
- Trusting the order Fantastical lists its weeks in: after Command T from another month the rows are listed out of date order, with rows no longer in sight among them. Days are ordered by where they are on the screen.
- Looking for suggestions once, 0.4 s after a key: people after "with" came up 1.3 s later. The list is looked for four times over about three seconds.
- Reading the keyboard only when it is on the view: Fantastical leaves it on the window after another app was in front, on the calendar set's button after Command 1 to 5, and on the split group after the notifications popover closes.

Untested: the Mac keyboard style, VoiceOver's keys, Fantastical in another language, braille.

## Evidence

[The module](../FantasticalAppModule.swift), whose comments date each observation. [Hand checks](../Tests/README.md). The unit test "fantastical:" in Sources/TurnOverTests/PureTests.swift covers the wording functions with made-up events.

## What would justify another attempt

- The year view: what pressing a day's button does.
- The mini window: "Added" and what Fantastical has understood, which are read from details the mini window does not show in a popover.
- Tasks and the task list.

## Decision

Continue: the module is used daily for some days before it is offered as a pull request.
