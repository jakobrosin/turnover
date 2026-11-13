// SPDX-License-Identifier: GPL-3.0-or-later
// Fantastical (12 Nov 2026; Fantastical 4.2.4, macOS 27.2, Windows keyboard style; found with turnover-plugin
// snapshot and try, and by ear). The month view gives accessibility everything: a scroll area described "Month
// view", in it an unnamed group for each week, in each week a group for each day described "Thursday, 12. November
// 2026, 5 events" (an AXUnknown when the day is empty: "…, No Events"), and in each day its events as static texts
// that can be pressed ("Title, from 12. November 2026 at 10:00 to 11:00, place, calendar"). With VoiceOver the days
// are reached by interacting with the view. TurnOver had the scroll area and then every event of seven weeks as one
// flat run: next item went from one event to the next with no day between them, a day with no events was never
// met, and nothing said which date an event was on (the days and events all report themselves disabled).
//
// TurnOver reads it as Calendar's module reads Apple's Calendar, a diary: Left and Right go a day at a time, Up and
// Down through that day's events, Option Up and Down a week at a time, Return opens the event (its popover), and
// Command T goes back to today. Moving past the first or last day shown turns the view with its own previous and
// next buttons. The quarter view is the same grid; the week and day views are read the same way from their own
// three areas (below). The keys are TurnOver's whenever the keyboard is on the view, on the window, or on the
// button beside the view where Command 1 to 5 leave it.
//
// An event's popover never takes the keyboard: TurnOver goes into it, Tab and Shift Tab move between its controls,
// Return or Space presses the ones that can't hold the keyboard, and Escape comes back to the event. Delete presses
// the event first, since Fantastical deletes what was last clicked, not what was last read.
//
// The new event field (Command N) says its suggestions as they come up and under Down and Up, what Fantastical has
// understood (Option Return), and what was added (Return, or Command Return from the event's other fields).
//
// No date is worked out here: the days are taken by where they are on the screen and known by their own words, so
// the region's date format doesn't matter. The words matched against Fantastical ("Month view", "No Events",
// "all-day", "Event details") are its English interface's; in another language the keys still move, with
// Fantastical's whole sentences.
import Foundation
import ApplicationServices

public final class FantasticalAppModule: AppModule {
    static let bundleID = "com.flexibits.fantastical2.mac"
    /// The mini window (the menu bar's) is another process, a login item inside Fantastical with the same sentence
    /// field: the module is registered for both.
    static let helperBundleID = "85C27NK92C.com.flexibits.fantastical2.mac.helper"
    /// The scroll area's description in the month view and in the quarter view, which is the same grid, longer.
    static let gridViews = ["Month view", "Quarter view"]

    /// Where the reading is: a day, by its date as Fantastical words it, and an event on it (nil: the day itself).
    private var current: String?
    private var eventIndex: Int?
    /// When TurnOver last moved (the view turned, an event opened): Fantastical's own focus news after it isn't read
    /// on top of TurnOver's words.
    private var lastOwnMove = Date.distantPast
    /// Return opened an event: waiting for its popover to take the focus, then for the focus to come back.
    private enum Opened { case no, waiting, showing }
    private var opened = Opened.no
    /// Go to Date's field: which part of the date the keyboard is on (its place in the field), and the date last known.
    private var datePart = 0
    private var dateKnown: Date?

    public required init(pid: pid_t, bundleIdentifier: String, appName: String) {
        super.init(pid: pid, bundleIdentifier: bundleIdentifier, appName: appName)
        let cat = "Fantastical"
        script("fantastical_nextDay", String(localized: "The next day, and how many events it has", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:rightArrow"], category: cat) { [weak self] g in self?.moveDays(1, g) }.isAvailable = { [weak self] in self?.inView() == true }
        script("fantastical_previousDay", String(localized: "The previous day", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:leftArrow"], category: cat) { [weak self] g in self?.moveDays(-1, g) }.isAvailable = { [weak self] in self?.inView() == true }
        script("fantastical_nextWeek", String(localized: "The same day next week", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:option+downArrow"], category: cat) { [weak self] g in self?.moveDays(7, g) }.isAvailable = { [weak self] in self?.inView() == true }
        script("fantastical_previousWeek", String(localized: "The same day last week", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:option+upArrow"], category: cat) { [weak self] g in self?.moveDays(-7, g) }.isAvailable = { [weak self] in self?.inView() == true }
        script("fantastical_nextEvent", String(localized: "The day's next event", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:downArrow"], category: cat) { [weak self] g in self?.moveEvent(1, g) }.isAvailable = { [weak self] in self?.inView() == true }
        script("fantastical_previousEvent", String(localized: "The day's previous event", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:upArrow"], category: cat) { [weak self] g in self?.moveEvent(-1, g) }.isAvailable = { [weak self] in self?.inView() == true }
        script("fantastical_open", String(localized: "Opens the event (its details)", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:enter"], category: cat) { [weak self] g in self?.openEvent(g) }.isAvailable = { [weak self] in self?.inView() == true && self?.eventIndex != nil }
        script("fantastical_today", String(localized: "Back to today", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:command+t"], category: cat) { [weak self] g in
            g.send()
            guard let self else { return }
            self.lastOwnMove = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.current = self.startingDay()?.label; self.eventIndex = nil
                self.sayDay()
            }
        }.isAvailable = { [weak self] in self?.inView() == true }
        // Fantastical's keyboard never goes into the popover and never comes back from it, so neither is news to
        // TurnOver: Escape closes it and the event is said again, back in the month view.
        script("fantastical_closeEvent", String(localized: "Closes the event's details, back to the event", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:escape"], category: cat) { [weak self] g in
            g.send()
            self?.leavePopover()
        }.isAvailable = { [weak self] in self?.opened == .showing }
        // The new event field (Command N): Fantastical's sentence field. Its suggestions (calendars after a slash,
        // places after "at", people after "with") come up as a list in a window of its own while the keyboard stays in
        // the field, so nothing was said of them and Down read the field's line again; and Return added the event
        // without a word (found with the key driver, 12 Nov 2026).
        for forward in [true, false] {
            script(forward ? "fantastical_nextSuggestion" : "fantastical_previousSuggestion",
                   forward ? String(localized: "In the new event field: the next suggestion", comment: "A command, as the key list and keyboard help say it") : String(localized: "In the new event field: the previous suggestion", comment: "A command, as the key list and keyboard help say it"),
                   gestures: [forward ? "kb:downArrow" : "kb:upArrow"], category: cat) { [weak self] g in
                g.send()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.saySuggestion() }
            }.isAvailable = { [weak self] in self?.inEntryField() == true && self?.suggestionTable() != nil }
        }
        script("fantastical_add", String(localized: "In the new event field: adds the event and says what was added; on a suggestion, takes it", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:enter", "kb:numpadEnter"], category: cat) { [weak self] g in self?.addFromEntry(g) }
            .isAvailable = { [weak self] in self?.inEntryField() == true }
        // Command Return adds the event from anywhere in the new event's popover, as silently.
        script("fantastical_addFromDetails", String(localized: "In a new event's details: adds the event and says what was added", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:command+enter"], category: cat) { [weak self] g in self?.addFromEntry(g, fromDetails: true) }
            .isAvailable = { [weak self] in self?.entryPopover() != nil }
        script("fantastical_understood", String(localized: "In the new event field: says what Fantastical has understood, without adding it", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:option+enter"], category: cat) { [weak self] _ in
            guard let self else { return }
            let words = self.entrySummary()
            Speech.cancel()
            Speech.speakMessage(words.isEmpty ? String(localized: "Nothing understood yet", comment: "Fantastical's new event field has no event worked out") : words)
        }.isAvailable = { [weak self] in self?.entryPopover() != nil }
        // Delete on an event. Fantastical deletes what it has selected, and its selection doesn't follow the reading:
        // the event's focus can be set (the call succeeds) and Delete still offered to delete another event, the one
        // last clicked (12 Nov 2026). Pressing the event is a click, which does select it. So the event TurnOver is on
        // is pressed, its popover's title is checked against it, and only then does the key go to Fantastical, which
        // asks before it deletes. Anything else, and nothing is sent.
        script("fantastical_delete", String(localized: "Deletes the event you are on; Fantastical asks first", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:backspace", "kb:command+backspace", "kb:delete"], category: cat) { [weak self] g in self?.deleteEvent(g) }
            .isAvailable = { [weak self] in self?.inView() == true }
        // In the popover Fantastical's own Tab went nowhere (12 Nov 2026: "tab and shift tab don't move between the
        // options"): the keyboard is still on the month view behind it. Tab and Shift Tab are TurnOver's there, through
        // the popover's controls in order, round.
        script("fantastical_popoverNext", String(localized: "In an event's details: the next control", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:tab"], category: cat) { [weak self] g in self?.moveInPopover(1, g) }
            .isAvailable = { [weak self] in self?.opened == .showing || self?.notificationsPopover() != nil }
        script("fantastical_popoverPrevious", String(localized: "In an event's details: the previous control", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:shift+tab"], category: cat) { [weak self] g in self?.moveInPopover(-1, g) }
            .isAvailable = { [weak self] in self?.opened == .showing || self?.notificationsPopover() != nil }
        // A control there that can't hold the keyboard (a button, a pop-up): Return or Space presses the one TurnOver is on.
        script("fantastical_popoverPress", String(localized: "In an event's details: presses the control you are on", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:enter", "kb:space"], category: cat) { [weak self] _ in
            guard let self, let e = self.restingControl() else { return }
            Tones.press()
            _ = AXUIElementPerformAction(e, kAXPressAction as CFString)
        }.isAvailable = { [weak self] in self?.restingControl() != nil }
        addDateFieldScripts(cat)
    }

    /// Go to Date (Shift Command T): the date field's day, month and year are one element, and nothing says which
    /// of them Tab or an arrow has moved to (13 Nov 2026). TurnOver keeps count and says the part.
    private func addDateFieldScripts(_ cat: String) {
        script("fantastical_nextDatePart", String(localized: "In Go to Date: the next part of the date (day, month, year)", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:rightArrow", "kb:tab"], category: cat) { [weak self] g in self?.moveDatePart(1, g) }
            .isAvailable = { [weak self] in self?.dateField() != nil }
        script("fantastical_previousDatePart", String(localized: "In Go to Date: the previous part of the date", comment: "A command, as the key list and keyboard help say it"), gestures: ["kb:leftArrow", "kb:shift+tab"], category: cat) { [weak self] g in self?.moveDatePart(-1, g) }
            .isAvailable = { [weak self] in self?.dateField() != nil }
    }

    public override func objectClass(for element: AXUIElement, role: Role, subrole: String?) -> TurnOverObject.Type? {
        guard element.role == "AXDateTimeArea", inPopover(element) else { return nil }
        return FantasticalDateTimePart.self
    }

    // MARK: The view

    private func window() -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        return app.element(kAXFocusedWindowAttribute) ?? app.elements(kAXWindowsAttribute).first
    }

    private static func isMonthView(_ e: AXUIElement) -> Bool {
        e.role == "AXScrollArea" && gridViews.contains(e.string(kAXDescriptionAttribute) ?? "")
    }

    /// The first element under `root` that `match` accepts, a few levels down and no further: the window's own parts,
    /// not the events of seven weeks.
    private static func find(in root: AXUIElement, depth: Int, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(root) { return root }
        guard depth > 0 else { return nil }
        for child in root.elements(kAXChildrenAttribute) {
            if let found = find(in: child, depth: depth - 1, match) { return found }
        }
        return nil
    }

    /// The month view's scroll area, if the window shows one.
    private func monthArea() -> AXUIElement? {
        guard let w = window() else { return nil }
        return Self.find(in: w, depth: 3, Self.isMonthView)
    }

    /// The keyboard is in the month view (not the search field, a sheet or an event's popover).
    func inView() -> Bool {
        guard let f = API.focusObject, f.pid == pid else { return false }
        // The window itself has the keyboard after another app was in front, and Fantastical takes its own arrows
        // there (a month a press): the grid is as much in use as when the keyboard is on it.
        if f.element.role == "AXWindow", Self.isCalendarWindow(f.element) { return monthArea() != nil || columnAreas() != nil }
        // Or its split group, where the keyboard is left as the notifications popover closes, or the group the view is in.
        if f.element.role == "AXSplitGroup" { return monthArea() != nil || columnAreas() != nil }
        if f.element.role == "AXGroup", f.element.elements(kAXChildrenAttribute).contains(where: { Self.isMonthView($0) || Self.isColumnArea($0) }) { return true }
        // Command 1 to 5 change the view and leave the keyboard on the calendar set's button, beside the view: the
        // arrows did Fantastical's own jumps there until Tab was pressed (found with the key driver, 12 Nov 2026).
        if f.element.role == "AXButton", let beside = f.element.element(kAXParentAttribute)?.elements(kAXChildrenAttribute),
           beside.contains(where: { Self.isMonthView($0) || Self.isColumnArea($0) }) { return true }
        return inArea(f.element)
    }
    /// A calendar window, by its identifier: "calendar-0", and "calendar-1" for a second one (File, New Window).
    private static func isCalendarWindow(_ w: AXUIElement) -> Bool { (w.string(kAXIdentifierAttribute) ?? "").hasPrefix("calendar-") }

    private func inArea(_ element: AXUIElement) -> Bool {
        var e: AXUIElement? = element
        var hops = 0
        while let x = e, hops < 6 {
            if Self.isMonthView(x) || Self.isColumnArea(x) { return true }
            if ["AXTextField", "AXTextArea", "AXSheet", "AXPopover"].contains(x.role) { return false }
            e = x.element(kAXParentAttribute); hops += 1
        }
        return false
    }

    private func inPopover(_ element: AXUIElement) -> Bool {
        var e: AXUIElement? = element
        var hops = 0
        while let x = e, hops < 10 { if x.role == "AXPopover" || x.role == "AXSheet" { return true }; e = x.element(kAXParentAttribute); hops += 1 }
        return false
    }

    /// A day as Fantastical lists it: its whole sentence, and the date alone ("Thursday, 12. November 2026").
    struct Day { let element: AXUIElement; let words: String; let label: String }

    /// The days the view lists, in order: every week's days, the empty ones too.
    private func days() -> [Day] {
        guard let area = monthArea() else { return columnDays() }
        // By where they are on the screen, not as listed: Fantastical uses its week rows again as the view scrolls,
        // and after a jump (Command T from December) lists them out of order, with rows no longer in sight among
        // them. Option Up from today went to 17 December (found with the key driver, 12 Nov 2026).
        let bounds = Self.frame(area)
        var weeks = area.elements(kAXChildrenAttribute).filter { $0.role == "AXGroup" }.map { (element: $0, frame: Self.frame($0)) }
        if let bounds, weeks.allSatisfy({ $0.frame != nil }) {
            weeks = weeks.filter { $0.frame!.intersects(bounds) }.sorted { $0.frame!.minY < $1.frame!.minY }
        }
        return weeks.flatMap { week -> [Day] in
            var row = week.element.elements(kAXChildrenAttribute).compactMap { e -> (day: Day, x: CGFloat?)? in
                guard ["AXGroup", "AXUnknown"].contains(e.role), let words = e.string(kAXDescriptionAttribute), !words.isEmpty else { return nil }
                return (Day(element: e, words: words, label: Self.dateLabel(words)), Self.frame(e)?.minX)
            }
            if row.allSatisfy({ $0.x != nil }) { row.sort { $0.x! < $1.x! } }
            return row.map(\.day)
        }
    }

    // MARK: The week and day views

    /// The week and day views (found with snapshots, 12 Nov 2026) are three scroll areas side by side in the window:
    /// "days", a button a day ("Tuesday, 10. November 2026, 4 events", the day's whole count); "all day events" and
    /// "timed events", each a group a day with that day's events of the kind. The keyboard never reaches the events:
    /// Tab goes round the toolbar, and Fantastical's own arrows move its day. Read here as the month view is: the
    /// days from the first area, each day's events from the other two, the all-day ones first.
    static let columnViews = ["days", "timed events", "all day events"]
    private static func isColumnArea(_ e: AXUIElement) -> Bool {
        e.role == "AXScrollArea" && columnViews.contains(e.string(kAXDescriptionAttribute) ?? "")
    }
    private func columnAreas() -> [String: AXUIElement]? {
        guard let w = window() else { return nil }
        var out: [String: AXUIElement] = [:]
        func walk(_ e: AXUIElement, _ depth: Int) {
            if Self.isColumnArea(e) { out[e.string(kAXDescriptionAttribute) ?? ""] = e; return }
            guard depth < 3, e.role != "AXToolbar" else { return }
            for c in e.elements(kAXChildrenAttribute) { walk(c, depth + 1) }
        }
        walk(w, 0)
        return out["days"] != nil && out["timed events"] != nil ? out : nil
    }

    private func columnDays() -> [Day] {
        guard let area = columnAreas()?["days"] else { return [] }
        var row = area.elements(kAXChildrenAttribute).compactMap { e -> (day: Day, x: CGFloat?)? in
            guard ["AXButton", "AXGroup", "AXUnknown"].contains(e.role), let words = e.string(kAXDescriptionAttribute), !words.isEmpty else { return nil }
            return (Day(element: e, words: words, label: Self.dateLabel(words)), Self.frame(e)?.minX)
        }
        if row.allSatisfy({ $0.x != nil }) { row.sort { $0.x! < $1.x! } }
        return row.map(\.day)
    }

    /// A day's events in the week and day views: from its group in each of the two event areas.
    private func columnEvents(_ day: Day, in areas: [String: AXUIElement]) -> [AXUIElement] {
        ["all day events", "timed events"].flatMap { name -> [AXUIElement] in
            guard let area = areas[name],
                  let group = area.elements(kAXChildrenAttribute).first(where: { Self.dateLabel($0.string(kAXDescriptionAttribute) ?? "") == day.label }) else { return [] }
            return pressable(in: group)
        }
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard axValue(e.attr(kAXPositionAttribute), .cgPoint, &origin), axValue(e.attr(kAXSizeAttribute), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The date of a day's sentence, without its count and weather: "Thursday, 12. November 2026, 5 events, Sleet,
    /// High 6°, Low 1°" is "Thursday, 12. November 2026". The whole sentence when the count isn't found.
    public static func dateLabel(_ words: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #", (?:\d+ (?:all day )?events?|No (?:All Day )?Events)(?:,|$)"#, options: [.caseInsensitive]),
              let m = re.firstMatch(in: words, range: NSRange(location: 0, length: (words as NSString).length)) else { return words }
        return (words as NSString).substring(to: m.range.location)
    }

    /// The date without its weekday, as events repeat it: "Thursday, 12. November 2026" is "12. November 2026".
    public static func dateAlone(_ label: String) -> String {
        guard let comma = label.range(of: ", ") else { return label }
        return String(label[comma.upperBound...])
    }

    /// A day's events: the texts that can be pressed (the weather line can't).
    private func events(_ day: Day) -> [AXUIElement] {
        if monthArea() == nil, let areas = columnAreas() { return columnEvents(day, in: areas) }
        return pressable(in: day.element)
    }

    private func pressable(in group: AXUIElement) -> [AXUIElement] {
        group.elements(kAXChildrenAttribute).filter { e in
            guard e.role == "AXStaticText" else { return false }
            var names: CFArray?
            guard AXUIElementCopyActionNames(e, &names) == .success, let list = names as? [String] else { return false }
            return list.contains(kAXPressAction as String)
        }
    }

    private static func text(of event: AXUIElement) -> String {
        for attribute in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
            if let s = event.string(attribute as String), !s.isEmpty { return s }
        }
        return ""
    }

    // MARK: Moving

    /// Today as the Mac writes a whole date, which is how Fantastical words its days.
    private static var todayLabel: String { DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none) }

    /// Where reading starts when TurnOver's day isn't in view: today if the view shows it, else its first day.
    private func startingDay() -> Day? {
        let all = days()
        let today = Self.todayLabel
        return all.first { $0.label == today } ?? all.first
    }

    private func dayShowing(_ label: String?) -> Day? {
        guard let label else { return nil }
        return days().first { $0.label == label }
    }

    /// The view's own previous or next button, in its toolbar.
    private func turnPage(forward: Bool) -> Bool {
        lastOwnMove = Date()
        let wanted = forward ? "move right a page" : "move left a page"
        guard let w = window(), let b = Self.find(in: w, depth: 4, { $0.string(kAXIdentifierAttribute) == wanted }) else { return false }
        return AXUIElementPerformAction(b, kAXPressAction as CFString) == .success
    }

    private func moveDays(_ n: Int, _ g: KeyboardGesture) {
        var all = days()
        guard !all.isEmpty else { g.send(); return }
        if dayShowing(current) == nil { current = startingDay()?.label; eventIndex = nil }
        guard var i = all.firstIndex(where: { $0.label == current }) else { return }
        var target = i + n
        var tries = 0
        // Past the days shown: the view is turned, and the day left is found again in what it shows then (a turn
        // moves the view by a month, so the weeks at its edge stay in sight). Gone from sight, the reading starts at
        // the near edge of the new days, in the same weekday's column for a week's move.
        while !all.indices.contains(target), tries < 3 {
            let anchor = all[i].label, edge = all.first?.label
            guard turnPage(forward: n > 0) else { break }
            _ = Poll.pumping(every: 0.02, limit: 1.0) { self.days().first?.label != edge }
            all = days()
            guard !all.isEmpty else { break }
            if let j = all.firstIndex(where: { $0.label == anchor }) {
                i = j; target = j + n
            } else {
                let column = i % 7
                target = n > 0 ? (n == 1 ? 0 : min(column, all.count - 1)) : (n == -1 ? all.count - 1 : max(0, all.count - 7 + column))
            }
            tries += 1
        }
        guard all.indices.contains(target) else { Tones.edge(); Log.io("fantastical: no day \(n > 0 ? "after" : "before") the ones shown"); return }
        current = all[target].label; eventIndex = nil
        lastOwnMove = Date()
        sayDay()
    }

    private func sayDay(prefix: String = "") {
        guard let day = dayShowing(current) else { return }
        let words = day.label == Self.todayLabel ? String(localized: "Today, \(day.words)", comment: "A Fantastical day that is today: %@ is the day as Fantastical words it") : day.words
        Speech.cancel()
        Speech.speakMessage(prefix + words)
    }

    private func moveEvent(_ step: Int, _ g: KeyboardGesture) {
        if dayShowing(current) == nil { current = startingDay()?.label; eventIndex = nil }
        guard let day = dayShowing(current) else { g.send(); return }
        let list = events(day)
        guard !list.isEmpty else { Tones.edge(); Speech.speakMessage(String(localized: "no events", comment: "Spoken message")); return }
        let next: Int
        if let i = eventIndex { next = i + step } else { next = step > 0 ? 0 : -1 }
        if next < 0 { eventIndex = nil; Tones.edge(); sayDay(); return }   // above the first: the day again
        guard next < list.count else { Tones.edge(); return }
        eventIndex = next
        sayEvent()
    }

    private func sayEvent() {
        guard let day = dayShowing(current), let i = eventIndex else { return }
        let list = events(day)
        guard i < list.count else { return }
        Speech.cancel()
        Speech.speakMessage("\(Self.brief(Self.text(of: list[i]), dayDate: Self.dateAlone(day.label))), \(Phrases.position(i + 1, of: list.count))")
    }

    private func openEvent(_ g: KeyboardGesture) {
        guard let day = dayShowing(current), let i = eventIndex, i < events(day).count else { g.send(); return }
        Tones.press()
        opened = .waiting
        lastOwnMove = Date()
        _ = AXUIElementPerformAction(events(day)[i], kAXPressAction as CFString)
        enterPopover()
    }

    private func deleteEvent(_ g: KeyboardGesture) {
        guard let day = dayShowing(current), let i = eventIndex, i < events(day).count else {
            Tones.edge()
            Speech.speakMessage(String(localized: "No event to delete: Down arrow to an event first", comment: "Delete pressed in Fantastical's month view on a day, not an event"))
            return
        }
        let event = events(day)[i], words = Self.text(of: event)
        _ = AXUIElementPerformAction(event, kAXPressAction as CFString)
        lastOwnMove = Date()
        // Waited for until its title is there, not only until it exists: the popover was found 0.2 s after the press
        // with its title still empty, and every Delete was refused (13 Nov 2026).
        var title = ""
        _ = Poll.pumping(every: 0.1, limit: 2.0) {
            guard let box = self.openPopover(),
                  let shown = Self.find(in: box, depth: 3, { $0.role == "AXTextField" && $0.string(kAXIdentifierAttribute) == "title" })?
                    .string(kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines), !shown.isEmpty else { return false }
            title = shown
            return true
        }
        guard !title.isEmpty, words.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(title) else {
            Tones.edge(); Log.io("fantastical: delete not sent: the event's popover didn't open or names another event (title \(title.count) characters, event \(words.count))")
            Speech.speakMessage(String(localized: "Could not select this event in Fantastical. Nothing was deleted.", comment: "Delete in Fantastical: the event could not be selected first"))
            return
        }
        Log.io("fantastical: the event is selected (its popover's title matches); the delete key goes on")
        opened = .no; eventIndex = nil
        g.send()
    }

    // MARK: The event's popover

    /// The controls a popover's reading starts on, in the order met.
    static let popoverRoles: Set<String> = ["AXTextField", "AXTextArea", "AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXComboBox", "AXDateTimeArea", "AXStaticText", "AXLink"]

    /// The popover Fantastical has open. Looked for everywhere it could hang: under the application and its windows,
    /// and under the month view's own days and events (the first search, of the windows without the month view, found
    /// none though the popover was there: 12 Nov 2026).
    private func openPopover() -> AXUIElement? {
        // Where it was found on 12 Nov 2026: a child of the week's group in the month view, beside that week's days.
        if let area = monthArea() {
            for week in area.elements(kAXChildrenAttribute) where week.role == "AXGroup" {
                if let box = week.elements(kAXChildrenAttribute).first(where: Self.isEventPopover) { return box }
            }
        }
        // In the week and day views: in one of their three areas, or under a day's group there.
        for area in (columnAreas() ?? [:]).values {
            for child in area.elements(kAXChildrenAttribute) {
                if Self.isEventPopover(child) { return child }
                if child.role == "AXGroup", let box = child.elements(kAXChildrenAttribute).first(where: Self.isEventPopover) { return box }
            }
        }
        let app = AXUIElementCreateApplication(pid)
        var queue = app.elements(kAXWindowsAttribute) + app.elements(kAXChildrenAttribute)
        var seen = 0
        while !queue.isEmpty, seen < 700 {
            let e = queue.removeFirst(); seen += 1
            let role = e.role
            if role == "AXPopover" {
                if Self.isEventPopover(e) { return e }
                continue
            }
            if role == "AXMenuBar" || role == "AXStaticText" && e.elements(kAXChildrenAttribute).isEmpty { continue }
            queue.append(contentsOf: e.elements(kAXChildrenAttribute))
        }
        return nil
    }

    /// An event's own popover: the one with "Event details" in it and no sentence field. Not any popover: once
    /// notifications have been shown, their popover stays in the window's toolbar though closed, and was taken for the
    /// event's wherever the first look came up empty. In the week view Return went into the notifications, and Delete
    /// was refused, its title never found (13 Nov 2026).
    private static func isEventPopover(_ e: AXUIElement) -> Bool {
        guard e.role == "AXPopover" else { return false }
        let children = e.elements(kAXChildrenAttribute)
        guard children.contains(where: { $0.role == "AXScrollArea" && $0.string(kAXDescriptionAttribute) == "Event details" }) else { return false }
        return find(in: e, depth: 2, { $0.string(kAXIdentifierAttribute) == entryField }) == nil
    }
    /// The pressed event's popover opens (AXCreated, 17 ms after the press) but Fantastical leaves the keyboard on the
    /// month view, so nothing was said and the popover couldn't be read (12 Nov 2026: "Enter on an event doesn't
    /// work"). TurnOver goes into it itself: its first control is given the focus and read.
    private func enterPopover() {
        guard Poll.pumping(every: 0.15, limit: 1.5, { self.openPopover() != nil }), let box = openPopover() else {
            opened = .no
            Tones.edge(); Log.io("fantastical: no popover after the press")
            return
        }
        var parts: [AXUIElement] = []
        var seen = 0
        func walk(_ e: AXUIElement) {
            seen += 1; guard seen < 120 else { return }
            if Self.popoverRoles.contains(e.role) { parts.append(e) }
            for c in e.elements(kAXChildrenAttribute) { walk(c) }
        }
        walk(box)
        opened = .showing
        lastOwnMove = Date()
        let first = parts.first { ($0.attr(kAXEnabledAttribute) as? Bool) != false } ?? parts.first ?? box
        _ = first.set(kAXFocusedAttribute, kCFBooleanTrue)
        AXHandler.shared.focusChanged(first, pid: pid)
    }

    /// The controls Tab stops on.
    static let stopRoles: Set<String> = ["AXTextField", "AXTextArea", "AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXComboBox", "AXDateTimeArea", "AXDisclosureTriangle", "AXLink"]
    /// Of those, the ones pressed rather than typed in.
    static let pressedRoles: Set<String> = ["AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXDisclosureTriangle", "AXLink"]

    /// The popover's controls in reading order, the disabled ones and its scroll bars' parts left out.
    private func stops(_ box: AXUIElement) -> [AXUIElement] {
        var out: [AXUIElement] = []
        var seen = 0
        func walk(_ e: AXUIElement) {
            seen += 1; guard seen < 200 else { return }
            let role = e.role
            if role == "AXScrollBar" { return }
            if Self.stopRoles.contains(role), (e.attr(kAXEnabledAttribute) as? Bool) != false { out.append(e) }
            for c in e.elements(kAXChildrenAttribute) { walk(c) }
        }
        walk(box)
        // Fantastical lists the four as start time, end time, start date, end date; read as a sentence is: the start's
        // date and time, then the end's.
        let wanted = ["start date", "start time", "end date", "end time"]
        let slots = out.indices.filter { out[$0].role == "AXDateTimeArea" }
        let named = wanted.compactMap { id in slots.map { out[$0] }.first { $0.string(kAXIdentifierAttribute) == id } }
        if slots.count == 4, named.count == 4 { for (slot, e) in zip(slots, named) { out[slot] = e } }
        return out
    }

    private func moveInPopover(_ by: Int, _ g: KeyboardGesture) {
        let notifications = notificationsPopover()
        guard let box = notifications ?? openPopover() else { opened = .no; g.send(); return }
        let all = notifications != nil ? notificationStops(box) : stops(box)
        guard !all.isEmpty else { Tones.edge(); return }
        let here = API.focusObject.flatMap { f in all.firstIndex { $0.isSame(f.element) } }
        let next = here.map { ($0 + by + all.count) % all.count } ?? (by > 0 ? 0 : all.count - 1)
        if here != nil, (by > 0 && next == 0) || (by < 0 && next == all.count - 1) { Tones.edge() }   // round to the other end
        lastOwnMove = Date()
        _ = all[next].set(kAXFocusedAttribute, kCFBooleanTrue)
        AXHandler.shared.focusChanged(all[next], pid: pid)
    }

    /// The pressed kind of control TurnOver is on in the popover, when the keyboard itself isn't on it (Fantastical
    /// wouldn't give it the focus): Return and Space press it. Nil where the keyboard is really there, or in a field.
    private func restingControl() -> AXUIElement? {
        guard let f = API.focusObject, f.pid == pid, Self.pressedRoles.contains(f.element.role), inPopover(f.element),
              opened == .showing || notificationsPopover() != nil,
              (f.element.attr(kAXFocusedAttribute) as? Bool) != true else { return nil }
        return f.element
    }

    // MARK: Notifications (Shift Command N)

    /// The notifications popover, when the keyboard is in it: the popover headed "Notifications". Its list takes the
    /// keyboard and reads by itself, a row an invitation ("Title, From:, Name, Fri, 13. Nov 20:00, Maybe, Accept,
    /// Decline"); but Tab went from Maybe to Decline, and Accept was never reached (the key driver, 12 Nov 2026).
    private func notificationsPopover() -> AXUIElement? {
        guard let f = API.focusObject, f.pid == pid else { return nil }
        var e: AXUIElement? = f.element
        var hops = 0
        while let x = e, hops < 8 {
            if x.role == "AXPopover" {
                return x.elements(kAXChildrenAttribute).contains { $0.role == "AXStaticText" && $0.string(kAXValueAttribute) == "Notifications" } ? x : nil
            }
            if x.role == "AXWindow" { return nil }
            e = x.element(kAXParentAttribute); hops += 1
        }
        return nil
    }

    /// Tab's stops there: the list, then the buttons of the invitation TurnOver is on (the row with the focus in it,
    /// else the selected one, else the first), every one of them.
    private func notificationStops(_ box: AXUIElement) -> [AXUIElement] {
        guard let table = Self.find(in: box, depth: 3, { $0.role == "AXTable" }) else { return [] }
        let all = rows(table)
        var row: AXUIElement?
        var e: AXUIElement? = API.focusObject?.element
        var hops = 0
        while let x = e, hops < 5, row == nil { if x.role == "AXRow" { row = x }; e = x.element(kAXParentAttribute); hops += 1 }
        row = row ?? selectedRow(table, among: all).map { all[$0] } ?? all.first
        var buttons: [AXUIElement] = []
        func walk(_ x: AXUIElement, _ depth: Int) {
            if x.role == "AXButton" { buttons.append(x); return }
            guard depth < 3 else { return }
            for c in x.elements(kAXChildrenAttribute) { walk(c, depth + 1) }
        }
        if let row { walk(row, 0) }
        return [table] + buttons
    }

    /// Escape went to Fantastical: once the popover has gone, TurnOver is back on the month view and says the event.
    private func leavePopover() {
        _ = Poll.pumping(every: 0.15, limit: 0.9) { self.openPopover() == nil }
        opened = .no
        lastOwnMove = Date()
        if let area = monthArea() ?? columnAreas()?["timed events"] { AXHandler.shared.focusChanged(area, pid: pid) }
        sayEvent()
    }

    /// Focus news inside the month view just after TurnOver's own move is Fantastical following it: not read. Arriving
    /// in the view, the view and the day in a line. Back from an opened event (Escape), the event again.
    public override func handleEvent(_ event: Event, next: () -> Void) {
        // The window's title changes as the view turns ("Month (December 2026)"): after TurnOver's own move the day it
        // says is the news.
        if event.kind == .nameChange, event.obj.pid == pid, event.obj.element.role == "AXWindow", Date().timeIntervalSince(lastOwnMove) < 1.5 { return }
        if event.kind == .typedCharacter, event.obj.pid == pid, event.obj.element.string(kAXIdentifierAttribute) == Self.entryField { suggestionsSoon() }
        if event.obj.pid == pid, Self.isSheetDateField(event.obj.element) {
            let parts = Self.dateParts(of: event.obj.element), now = event.obj.element.attr(kAXValueAttribute) as? Date
            // Tab comes in at the first part, Shift Tab at the last (checked with the key driver, 13 Nov 2026).
            if event.kind == .gainFocus { datePart = InputManager.lastKeyIdentifier.hasSuffix("shift+tab") ? max(0, parts.count - 1) : 0 }
            // The part that changed is the part the keyboard is on, whatever was counted (a click moves it too).
            if event.kind == .valueChange, let before = dateKnown, let now, let changed = Self.changedPart(from: before, to: now, calendar: .current),
               let i = parts.firstIndex(of: changed) {
                datePart = i
                dateKnown = now
                // The new value first, then the date it makes ("15, Sunday, 15. November 2026"): the value is the
                // news, and the whole date took too long to get to it (Jakob, 13 Nov 2026).
                if API.focusObject?.element.isSame(event.obj.element) == true {
                    let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
                    Speech.speakMessage(Self.changeWords(changed, of: now, whole: f.string(from: now), calendar: .current, locale: .current))
                    return
                }
            }
            dateKnown = now
        }
        if [.gainFocus, .focusEntered].contains(event.kind), event.obj.pid == pid, inArea(event.obj.element) {
            // First: the week view reports its own focus again as an event's popover opens, which read as the popover
            // closing (the event said again, and Escape no longer TurnOver's).
            if Date().timeIntervalSince(lastOwnMove) < 1.0 { return }
            if opened == .showing {
                opened = .no
                lastOwnMove = Date()
                DispatchQueue.main.async { [weak self] in self?.sayEvent() }
                return
            }
            if event.kind == .gainFocus, Self.isMonthView(event.obj.element) || Self.isColumnArea(event.obj.element) {
                lastOwnMove = Date()
                if dayShowing(current) == nil { current = startingDay()?.label; eventIndex = nil }
                DispatchQueue.main.async { [weak self] in
                    let view = event.obj.element.string(kAXDescriptionAttribute) ?? ""   // Fantastical's own words: "Month view"
                    self?.sayDay(prefix: view.isEmpty || Self.columnViews.contains(view) ? "" : view + ", ")
                }
                return
            }
        }
        if opened == .waiting, [.gainFocus, .focusEntered].contains(event.kind), event.obj.pid == pid, inPopover(event.obj.element) { opened = .showing }
        next()
    }

    /// Fantastical says the date it has scrolled to as its view turns ("Tuesday, 1. December 2026" on the way to 24
    /// December): after TurnOver's own move the day TurnOver says is the news, not that.
    public override func ignoresAnnouncement(_ text: String, after key: String, elapsed: TimeInterval) -> Bool {
        // Go to Date's field says its new date itself at each change, and TurnOver says the field's new value: once.
        Date().timeIntervalSince(lastOwnMove) < 1.5 || dateField() != nil
    }

    // MARK: Go to Date

    public enum DatePart: Sendable { case day, month, year }

    /// The parts of a date in the order a format writes them ("d. MMMM y": day, month, year), which is the order
    /// they stand in the field.
    nonisolated public static func dateParts(format: String) -> [DatePart] {
        var out: [DatePart] = [], quoted = false
        for c in format {
            if c == "'" { quoted.toggle(); continue }
            if quoted { continue }
            let part: DatePart? = "dD".contains(c) ? .day : "ML".contains(c) ? .month : "yYu".contains(c) ? .year : nil
            if let part, !out.contains(part) { out.append(part) }
        }
        return out
    }

    /// The part two dates differ in. The largest one: the day follows a month or a year into a shorter month (31
    /// January, a month on, is 28 February).
    nonisolated public static func changedPart(from a: Date, to b: Date, calendar: Calendar) -> DatePart? {
        let x = calendar.dateComponents([.year, .month, .day], from: a), y = calendar.dateComponents([.year, .month, .day], from: b)
        if x.year != y.year { return .year }
        if x.month != y.month { return .month }
        return x.day != y.day ? .day : nil
    }

    /// A date field in a sheet that shows a date and no time (NSDatePicker's element flags: 0xe0 the date's parts,
    /// 0x0e the time's): Go to Date's. An event's own date and time controls are in a popover and keep their ways.
    static func isSheetDateField(_ e: AXUIElement) -> Bool {
        guard e.role == "AXDateTimeArea", e.element(kAXParentAttribute)?.role == "AXSheet" else { return false }
        guard let flags = (e.attr("AXDateTimeComponents") as? NSNumber)?.intValue else { return true }
        return flags & 0xe0 != 0 && flags & 0x0e == 0
    }

    /// The field's parts, in the region's order, without the ones it doesn't show.
    static func dateParts(of e: AXUIElement) -> [DatePart] {
        let flags = (e.attr("AXDateTimeComponents") as? NSNumber)?.intValue ?? 0xe0
        let shown: [DatePart: Int] = [.day: 0x20, .month: 0x40, .year: 0x80]
        return dateParts(format: DateFormatter.dateFormat(fromTemplate: "yMMMMd", options: 0, locale: .current) ?? "d MMMM y")
            .filter { flags & (shown[$0] ?? 0) != 0 }
    }

    private func dateField() -> AXUIElement? {
        guard let f = API.focusObject, f.pid == pid, Self.isSheetDateField(f.element) else { return nil }
        return f.element
    }

    /// Tab and Shift Tab go through the parts and then out of the field; the arrows go round. The key is
    /// Fantastical's; TurnOver says where it landed.
    private func moveDatePart(_ step: Int, _ g: KeyboardGesture) {
        guard let field = dateField() else { g.send(); return }
        let parts = Self.dateParts(of: field)
        var i = datePart + step
        let tab = g.keyCode == 48
        guard parts.count > 1, !tab || parts.indices.contains(i) else { g.send(); return }   // Tab off the end: the next control
        i = (i + parts.count) % parts.count
        g.send()
        datePart = i
        // Only if the keyboard is still in the field a moment later (the count can be out after a click).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let now = self.dateField(), now.isSame(field), parts.indices.contains(self.datePart),
                  let date = now.attr(kAXValueAttribute) as? Date else { return }
            Speech.speakMessage(Self.partWords(parts[self.datePart], of: date, calendar: .current, locale: .current))
        }
    }

    /// A part's value alone: "14", "November", "2026".
    nonisolated public static func partValue(_ part: DatePart, of date: Date, calendar: Calendar, locale: Locale) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        switch part {
        case .day: return String(c.day ?? 0)
        case .month:
            let f = DateFormatter(); f.locale = locale; f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "LLLL"
            return f.string(from: date)
        case .year: return String(c.year ?? 0)
        }
    }

    /// "day 14", "month November", "year 2026".
    nonisolated public static func partWords(_ part: DatePart, of date: Date, calendar: Calendar, locale: Locale) -> String {
        let value = partValue(part, of: date, calendar: calendar, locale: locale)
        switch part {
        case .day: return String(localized: "day \(value)", comment: "Go to Date in Fantastical: the part of the date the keyboard is on, and its value")
        case .month: return String(localized: "month \(value)", comment: "Go to Date in Fantastical: the part of the date the keyboard is on, and its value")
        case .year: return String(localized: "year \(value)", comment: "Go to Date in Fantastical: the part of the date the keyboard is on, and its value")
        }
    }

    /// A change: the part's new value, then the whole date ("15, Sunday, 15. November 2026").
    nonisolated public static func changeWords(_ part: DatePart, of date: Date, whole: String, calendar: Calendar, locale: Locale) -> String {
        String(localized: "\(partValue(part, of: date, calendar: calendar, locale: locale)), \(whole)", comment: "Go to Date in Fantastical, after a change: the changed part's new value, then the whole date")
    }

    // MARK: The new event field

    /// The sentence field's identifier.
    static let entryField = "ParserInputTextView"

    private func inEntryField() -> Bool {
        guard let f = API.focusObject, f.pid == pid else { return false }
        return f.element.string(kAXIdentifierAttribute) == Self.entryField
    }

    /// The list of suggestions, when Fantastical shows one: a table in a window of its own, beside the calendar's.
    private func suggestionTable() -> AXUIElement? {
        // Not the window the field itself is in: the mini window has its event list, a table, under the field.
        let own = API.focusObject?.element.element(kAXWindowAttribute)
        for w in AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute) where !Self.isCalendarWindow(w) && !(own.map { $0.isSame(w) } ?? false) {
            if let t = Self.find(in: w, depth: 4, { ["AXTable", "AXOutline", "AXList"].contains($0.role) }) { return t }
        }
        return nil
    }

    private func rows(_ table: AXUIElement) -> [AXUIElement] {
        let listed = table.elements(kAXRowsAttribute)
        return listed.isEmpty ? table.elements(kAXChildrenAttribute).filter { $0.role == "AXRow" || $0.role == "AXStaticText" } : listed
    }

    /// A row's words: its texts, in order.
    private static func words(of row: AXUIElement) -> String {
        var out: [String] = []
        var seen = 0
        func walk(_ e: AXUIElement, _ depth: Int) {
            seen += 1; guard seen < 30, depth < 5 else { return }
            if ["AXStaticText", "AXTextField", "AXButton"].contains(e.role) {
                for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                    if let t = e.string(attribute as String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { if !out.contains(t) { out.append(t) }; break }
                }
            }
            for c in e.elements(kAXChildrenAttribute) { walk(c, depth + 1) }
        }
        walk(row, 0)
        return out.joined(separator: ", ")
    }

    private func selectedRow(_ table: AXUIElement, among all: [AXUIElement]) -> Int? {
        if let chosen = table.elements(kAXSelectedRowsAttribute).first, let i = all.firstIndex(where: { $0.isSame(chosen) }) { return i }
        return all.firstIndex { ($0.attr(kAXSelectedAttribute) as? Bool) == true }
    }

    private static func count(_ n: Int) -> String {
        n == 1 ? String(localized: "1 suggestion", comment: "Fantastical's suggestions for the new event field") : String(localized: "\(String(n)) suggestions", comment: "Fantastical's suggestions for the new event field")
    }

    /// After Down or Up: the suggestion Fantastical is on, or how many there are when it is on none.
    private func saySuggestion() {
        guard let table = suggestionTable() else { return }
        let all = rows(table)
        let real = all.indices.filter { !Self.isHeading(Self.words(of: all[$0])) }
        Speech.cancel()
        if let i = selectedRow(table, among: all), let place = real.firstIndex(of: i) {
            Speech.speakMessage("\(Self.words(of: all[i])), \(Phrases.position(place + 1, of: real.count))")
        } else { Speech.speakMessage(Self.count(real.count)) }
    }

    /// How many suggestions were last said of; -1, none showing.
    private var suggestionsSaid = -1
    private var suggestionCheck = 0

    /// A key was typed: once Fantastical has caught up, a list that has come up, or changed its length, is said by its
    /// first suggestion and how many there are. Once a burst of typing, not a letter at a time.
    private func suggestionsSoon() {
        suggestionCheck += 1
        let check = suggestionCheck
        // Looked for more than once: people after "with" came up 1.3 s after the last letter (Contacts is searched),
        // later than one look at 0.4 s, and nothing was said of them (12 Nov 2026).
        for delay in [0.4, 1.0, 1.8, 2.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, check == self.suggestionCheck, self.inEntryField() else { return }
                guard let table = self.suggestionTable() else { self.suggestionsSaid = -1; return }
                let all = self.rows(table).map { Self.words(of: $0) }.filter { !Self.isHeading($0) }
                guard !all.isEmpty, all.count != self.suggestionsSaid else { return }
                self.suggestionsSaid = all.count
                Speech.speakMessage("\(all[0]), \(Self.count(all.count))")
            }
        }
    }

    /// A row that heads a group of suggestions ("CONTACTS"), not one of them: all capitals.
    public static func isHeading(_ words: String) -> Bool {
        words.isEmpty || (words == words.uppercased() && words != words.lowercased() && !words.contains("@"))
    }

    /// The popover the sentence field is in, and in it the event Fantastical has made of the sentence so far.
    private func entryDetails() -> AXUIElement? {
        entryPopover().flatMap { Self.find(in: $0, depth: 2, { $0.role == "AXScrollArea" && $0.string(kAXDescriptionAttribute) == "Event details" }) }
    }

    /// The new event's popover, when the keyboard is anywhere in it: the one that holds the sentence field.
    private func entryPopover() -> AXUIElement? {
        guard let f = API.focusObject, f.pid == pid else { return nil }
        var e: AXUIElement? = f.element
        var hops = 0
        while let x = e, hops < 8 {
            if x.role == "AXPopover" { return Self.find(in: x, depth: 3, { $0.string(kAXIdentifierAttribute) == Self.entryField }) != nil ? x : nil }
            if x.role == "AXWindow" { return nil }
            e = x.element(kAXParentAttribute); hops += 1
        }
        return nil
    }

    /// What Fantastical has understood, in a line: "Lunch, Friday 13 November, 15:00 to 15:45, calendar Work, alert 15
    /// minutes before". Read from the details it shows under the field; empty before it has made anything of the words.
    private func entrySummary() -> String {
        guard let details = entryDetails() else { return "" }
        var parts: [AXUIElement] = []
        var seen = 0
        func walk(_ e: AXUIElement, _ depth: Int) {
            seen += 1; guard seen < 80, depth < 4 else { return }
            parts.append(e)
            for c in e.elements(kAXChildrenAttribute) { walk(c, depth + 1) }
        }
        walk(details, 0)
        func part(_ name: String) -> AXUIElement? {
            parts.first { $0.string(kAXIdentifierAttribute) == name || $0.string(kAXDescriptionAttribute) == name }
        }
        func text(_ name: String) -> String { (part(name)?.attr(kAXValueAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        func date(_ name: String) -> Date? { part(name)?.attr(kAXValueAttribute) as? Date }
        let title = text("title")
        guard !title.isEmpty else { return "" }
        let allDay = (part("is all day")?.attr(kAXValueAttribute) as? NSNumber)?.boolValue ?? false
        let start = date("start date") ?? date("start time"), end = date("end date") ?? date("end time")
        return Self.summary(title: title, task: text("item type") == "task", allDay: allDay, start: start, end: end,
                            location: text("location"), calendar: text("calendar"), alert: text("alarm type"))
    }

    /// The line itself, from what the details hold.
    public static func summary(title: String, task: Bool, allDay: Bool, start: Date?, end: Date?, location: String, calendar: String, alert: String,
                               locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let day = DateFormatter(); day.locale = locale; day.timeZone = timeZone; day.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let time = DateFormatter(); time.locale = locale; time.timeZone = timeZone; time.dateStyle = .none; time.timeStyle = .short
        var cal = Calendar.current; cal.timeZone = timeZone
        var out = [title]
        if task { out.append(String(localized: "task", comment: "Fantastical's new item is a task, not an event")) }
        if let start {
            let sameDay = end.map { cal.isDate($0, inSameDayAs: start) } ?? true
            if allDay {
                out.append(sameDay ? day.string(from: start) : String(localized: "\(day.string(from: start)) to \(day.string(from: end!))", comment: "An event over several days: its first and last day"))
                out.append(String(localized: "all day", comment: "A Calendar event lasting all day"))
            } else if let end, end != start {
                out.append(day.string(from: start))
                out.append(sameDay ? String(localized: "\(time.string(from: start)) to \(time.string(from: end))", comment: "An event's start and end times")
                                   : String(localized: "\(time.string(from: start)) to \(day.string(from: end)) \(time.string(from: end))", comment: "An event's start time, and its end on another day"))
            } else {
                out.append(day.string(from: start)); out.append(time.string(from: start))
            }
        }
        if !location.isEmpty { out.append(location) }
        if !calendar.isEmpty { out.append(String(localized: "calendar \(calendar)", comment: "The calendar a new Fantastical event goes in: %@ is its name")) }
        if !alert.isEmpty, alert != "None" { out.append(String(localized: "alert \(alert)", comment: "A new Fantastical event's alert: %@ is Fantastical's own words, 15 minutes before")) }
        return out.joined(separator: ", ")
    }

    /// Return in the sentence field. On a suggestion, Fantastical takes it into the sentence: the sentence is said as
    /// it then stands. Otherwise Fantastical adds the event and closes the field: what was added is said.
    private func addFromEntry(_ g: KeyboardGesture, fromDetails: Bool = false) {
        if !fromDetails, let table = suggestionTable(), selectedRow(table, among: rows(table)) != nil {
            let field = API.focusObject?.element
            g.send()
            suggestionsSaid = -1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let words = field?.attr(kAXValueAttribute) as? String, !words.isEmpty else { return }
                Speech.cancel(); Speech.speakMessage(words)
            }
            return
        }
        let words = entrySummary()
        let field = API.focusObject?.element
        g.send()
        suggestionsSaid = -1
        guard !words.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            // Still in the popover with its words: Fantastical didn't add it (it asked something, or wants more).
            if self.entryPopover() != nil, let left = field?.attr(kAXValueAttribute) as? String, !left.isEmpty { return }
            self.lastOwnMove = Date()
            Speech.speakMessage(String(localized: "Added: \(words)", comment: "Fantastical added the new event: %@ is the event in a line"))
        }
    }

    // MARK: Words

    /// An event without the date its day has already said: "Team meeting, from 12. November 2026 at 10:00 to 11:00,
    /// Room 2" on that day is "Team meeting, from 10:00 to 11:00, Room 2"; "Holiday, 12. November 2026, all-day,
    /// Holidays" is "Holiday, all day, Holidays". An event over several days keeps Fantastical's own sentence.
    public static func brief(_ text: String, dayDate: String) -> String {
        guard !dayDate.isEmpty else { return text }
        return text.replacingOccurrences(of: ", from \(dayDate) at ", with: ", from ")
            .replacingOccurrences(of: ", \(dayDate), all-day", with: ", " + String(localized: "all day", comment: "A Calendar event lasting all day"))
    }
}

/// The date and time controls of an event's popover. Each said the whole moment ("12 November 2026 at 10:00") whether
/// it showed the date or the time, so setting a time meant hearing the date through first, at every step (12 Nov
/// 2026). Each says what it shows: the date control the date, the time control the time.
final class FantasticalDateTimePart: TurnOverObject {
    /// What the control shows: by its own account (NSDatePicker's element flags: 0x0e the time's, 0xe0 the date's),
    /// or by its place among the popover's date and time controls, which come as date, time, date, time (two alone
    /// are an all-day event's two dates).
    private var showsTime: Bool? {
        // By its name first: "start time", "end date".
        let id = element.string(kAXIdentifierAttribute) ?? element.string(kAXDescriptionAttribute) ?? ""
        if id.hasSuffix("time") { return true }
        if id.hasSuffix("date") { return false }
        if let flags = (element.attr("AXDateTimeComponents") as? NSNumber)?.intValue {
            let time = flags & 0x0e != 0, date = flags & 0xe0 != 0
            if time != date { return time }
        }
        guard let parent = element.element(kAXParentAttribute) else { return nil }
        let all = parent.elements(kAXChildrenAttribute).filter { $0.role == "AXDateTimeArea" }
        guard all.count == 4, let i = all.firstIndex(where: { $0.isSame(element) }) else { return all.count == 2 ? false : nil }
        return i % 2 == 1
    }
    override var value: String? {
        guard let date = element.attr(kAXValueAttribute) as? Date, let time = showsTime else { return super.value }
        let f = DateFormatter()
        // Go to Date's field with the weekday, as Fantastical itself says each change there (13 Nov 2026).
        let sheet = element.element(kAXParentAttribute)?.role == "AXSheet"
        if time { f.dateStyle = .none; f.timeStyle = .short } else { f.dateStyle = sheet ? .full : .long; f.timeStyle = .none }
        return f.string(from: date)
    }
}
