import AltilloDesign
import SwiftUI

/// A deliberately small Reminders view: today's incomplete items and the next ones, with creation left to Ask.
struct DesvanRemindersView: View {
    let model: NotchModel

    private var store: RemindersStore { model.reminders }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { store.start() }
            .onDisappear { store.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.access {
        case .unknown:
            DesvanModuleNotice(
                symbol: "checklist",
                title: "Shall we look at your reminders?",
                message: "Altillo shows what's due and lets you mark it done. Your reminders never leave your Mac.",
                actionTitle: "Give access"
            ) {
                Task { await store.requestAccess() }
            }
        case .denied:
            DesvanModuleNotice(
                symbol: "checklist.unchecked",
                title: "Reminders are closed",
                message: "Allow Altillo in System Settings to see and complete your reminders.",
                actionTitle: "Open Settings"
            ) {
                PrivacySettings.reminders.open()
            }
        case .granted:
            grantedContent
        }
    }

    @ViewBuilder
    private var grantedContent: some View {
        if store.problem != nil {
            DesvanModuleNotice(
                symbol: "exclamationmark.triangle",
                title: "Couldn't update reminders",
                message: "Reminders couldn't be loaded. Try again.",
                actionTitle: "Try again"
            ) {
                store.refresh()
            }
        } else if !store.hasLoaded {
            DesvanModuleNotice(symbol: "checklist", title: "Checking your reminders…")
        } else if store.today.isEmpty && store.upcoming.isEmpty {
            DesvanModuleNotice(
                symbol: "checkmark.circle",
                title: "Nothing pending",
                message: "Your reminders are clear. Ask Altillo whenever you want to add one.",
                actionTitle: "Open Reminders"
            ) {
                store.openReminders()
            }
        } else {
            remindersList
        }
    }

    private var remindersList: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    if !store.today.isEmpty {
                        section("Today", items: store.today)
                    }
                    if !store.upcoming.isEmpty {
                        section("Upcoming", items: store.upcoming)
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)

            Button("Open Reminders") { store.openReminders() }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 27))
                .accessibilityHint("Opens the Reminders app")
        }
        .padding(14)
        .desvanCard(radius: 16)
    }

    private func section(_ title: LocalizedStringKey, items: [RemindersStore.Item]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            ForEach(items.prefix(6)) { item in
                DesvanReminderRow(item: item, store: store)
            }
            if items.count > 6 {
                Button("Show \(items.count - 6) more in Reminders") { store.openReminders() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .padding(.leading, 30)
            }
        }
    }
}

private struct DesvanReminderRow: View {
    let item: RemindersStore.Item
    let store: RemindersStore

    var body: some View {
        HStack(spacing: 8) {
            Button { store.complete(item) } label: {
                Image(systemName: "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark as completed")
            .accessibilityLabel("Complete \(item.title)")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { store.openReminders() } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .help("Open in Reminders")
            .accessibilityLabel("Open \(item.title) in Reminders")
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 36)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Desvan.Palette.paper.opacity(0.055))
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        guard let due = item.due else { return item.listName }
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(due)
        let day: String
        if isToday, item.dueHasTime {
            day = due.formatted(date: .omitted, time: .shortened)
        } else if isToday {
            day = String(localized: "Today")
        } else if item.dueHasTime {
            day = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        } else {
            day = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return "\(day) · \(item.listName)"
    }
}
