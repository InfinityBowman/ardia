import ArdiaBrowser
import ArdiaDesign
import SwiftUI

struct ArchiveView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var isConfirmingClear = false
  @State private var restoreTicks = 0
  @State private var deleteAllTicks = 0
  @State private var copyTicks = 0
  @State private var selection = Set<UUID>()
  @State private var editMode = EditMode.inactive

  var body: some View {
    NavigationStack {
      content
        .background(ArchivePalette.sheet.ignoresSafeArea())
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ArchiveSearch(query: $query, isShown: !app.tabs.archive.isEmpty))
        .environment(\.editMode, $editMode)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            if !app.tabs.archive.isEmpty { editButton }
          }
          ToolbarItem(placement: .topBarTrailing) { optionsMenu }
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
          ToolbarItem(placement: .topBarTrailing) { doneButton }
        }
        .confirmationDialog("Delete All Archived Tabs?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
          Button("Delete All", role: .destructive) {
            deleteAllTicks += 1
            app.tabs.clearArchive()
          }
        } message: {
          Text("This can’t be undone.")
        }
    }
    .sensoryFeedback(.selection, trigger: restoreTicks)
    .sensoryFeedback(.warning, trigger: deleteAllTicks)
    .sensoryFeedback(.success, trigger: copyTicks)
    .onAppear { app.tabs.loadArchive() }
  }

  @ViewBuilder private var content: some View {
    let days = app.tabs.archive
    if days.isEmpty {
      ArchiveEmptyState()
    } else if !trimmedQuery.isEmpty {
      let results = app.tabs.searchArchive(trimmedQuery)
      if results.isEmpty {
        ContentUnavailableView.search(text: trimmedQuery)
      } else {
        List(selection: $selection) {
          Section {
            ForEach(results, id: \.id) { tab in row(tab) }
          }
          .listRowBackground(ArchivePalette.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
      }
    } else {
      List(selection: $selection) {
        ForEach(days) { day in
          Section {
            ForEach(day.tabs, id: \.id) { tab in row(tab) }
          } header: {
            Text(ArchiveDayTitle.title(for: day.day))
              .font(.headline)
              .foregroundStyle(.secondary)
              .textCase(nil)
          }
          .listRowBackground(ArchivePalette.card)
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .safeAreaInset(edge: .bottom) {
        if editMode.isEditing, !selection.isEmpty {
          Button("Delete \(selection.count)", role: .destructive) {
            app.tabs.delete(selection)
            selection = []
            editMode = .inactive
          }
          .font(.body.weight(.semibold))
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .padding(.bottom, Spacing.small)
        }
      }
    }
  }

  private var editButton: some View {
    Button(editMode.isEditing ? "Done" : "Edit") {
      withAnimation {
        editMode = editMode.isEditing ? .inactive : .active
        if !editMode.isEditing { selection = [] }
      }
    }
    .font(.body.weight(.medium))
  }

  private var doneButton: some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "checkmark")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: ArchiveLayout.close, height: ArchiveLayout.close)
        .background(ArchivePalette.close, in: .circle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Done")
  }

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var optionsMenu: some View {
    Menu {
      Picker(selection: Bindable(app.tabs).autoArchiveInterval) {
        ForEach(AutoArchiveInterval.allCases) { option in
          Text(option.title).tag(option)
        }
      } label: {
        Label("Archive Inactive Tabs", systemImage: "archivebox")
      }
      .pickerStyle(.menu)
      Divider()
      Button("Delete All…", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
        .disabled(app.tabs.archive.isEmpty)
    } label: {
      Label("Options", systemImage: "ellipsis")
    }
  }

  private func row(_ tab: BrowserTab) -> some View {
    Button {
      guard !editMode.isEditing else { return }
      restoreTicks += 1
      app.restoreArchived(tab.id)
    } label: {
      ArchiveRow(tab: tab)
    }
    .buttonStyle(.plain)
    .listRowInsets(ArchiveLayout.rowInsets)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button("Delete", systemImage: "trash", role: .destructive) { app.tabs.delete([tab.id]) }
    }
    .contextMenu {
      Button("Open", systemImage: "arrow.up.forward.square") { app.restoreArchived(tab.id) }
      if let url = app.shareURL(of: tab) {
        Button("Copy Link", systemImage: "link") {
          app.copyLink(of: tab)
          copyTicks += 1
        }
        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
      }
      Divider()
      Button("Delete", systemImage: "trash", role: .destructive) { app.tabs.delete([tab.id]) }
    }
    .accessibilityHint("Reopens the tab.")
  }
}

struct ArchiveRow: View {
  let tab: BrowserTab
  @ScaledMetric(relativeTo: .body) private var iconSize = 20
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let iconSize = iconSize
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      FaviconImage(iconURL: tab.faviconURL, pageURL: tab.url, size: iconSize)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + iconSize * 0.25 }
      VStack(alignment: .leading, spacing: 2) {
        Text(TabText.title(for: tab))
          .font(.body)
          .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        Text(facts)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }

  private var facts: String {
    let host = TabText.host(for: tab)
    guard let archived = tab.archivedAt else { return host }
    return String(localized: "\(host) · \(archived.formatted(date: .omitted, time: .shortened))")
  }
}

enum ArchiveDayTitle {
  static func title(for day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
      return String(localized: "Yesterday")
    }
    if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), day >= weekAgo {
      return day.formatted(.dateTime.weekday(.wide))
    }
    let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
    return sameYear ? day.formatted(.dateTime.month(.wide).day()) : day.formatted(.dateTime.month(.wide).day().year())
  }
}

struct ArchiveEmptyState: View {
  var body: some View {
    VStack(spacing: Spacing.small) {
      Text("Nothing here yet!")
        .font(.title2.weight(.bold))
        .foregroundStyle(.primary)
      Text("Closed and auto-archived tabs will appear here. You can change how soon inactive tabs are archived with the ••• button.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, ArchiveLayout.emptyInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }
}

enum ArchivePalette {
  static let sheet = Color.adaptive(light: Color(.systemGroupedBackground), dark: Color(hex: 0x1C1C1D))
  static let card = Color.adaptive(light: Color(.secondarySystemGroupedBackground), dark: Color(hex: 0x2C2C2E))
  static let close = Color(hex: 0x7B8DF7)
}

enum ArchiveLayout {
  static let close: CGFloat = 44
  static let emptyInset: CGFloat = 40
  static let rowInsets = EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)
}

private struct ArchiveSearch: ViewModifier {
  @Binding var query: String
  let isShown: Bool

  func body(content: Content) -> some View {
    if isShown {
      content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
    } else {
      content
    }
  }
}
