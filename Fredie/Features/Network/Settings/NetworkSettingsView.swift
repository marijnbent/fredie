import Charts
import SwiftUI

struct NetworkSettingsView: View {
    @Environment(NetworkCoordinator.self) private var network
    @Environment(AppSettings.self) private var settings
    @State private var search = ""

    var body: some View {
        @Bindable var settings = settings
        @Bindable var network = network
        Form {
            Section {
                if settings.networkEnabled {
                    LabeledContent("Status", value: network.status)
                }
                LabeledContent("Protection", value: "Not active")
                if let error = network.error {
                    Text(error).foregroundStyle(.red)
                    Button("Restart monitoring") { network.restart() }
                        .disabled(!settings.networkEnabled)
                }
            }
            Section {
                Picker("Period", selection: $network.period) {
                    Text("Day").tag(UsagePeriod.today)
                    Text("7 days").tag(UsagePeriod.week)
                    Text("30 days").tag(UsagePeriod.month)
                }
                if network.period == .today {
                    DatePicker("Day", selection: $network.day, in: ...Date(), displayedComponents: .date)
                }
                LabeledContent("Downloaded", value: NetworkCoordinator.bytes(network.total.received))
                LabeledContent("Uploaded", value: NetworkCoordinator.bytes(network.total.sent))
                if network.period != .today, !network.days.isEmpty {
                    Chart(network.days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Download", day.traffic.received))
                            .foregroundStyle(Color.accentColor)
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Upload", day.traffic.sent))
                            .foregroundStyle(Color.accentColor.opacity(0.35))
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let bytes = value.as(Double.self) {
                                    Text(NetworkCoordinator.bytes(UInt64(max(0, bytes))))
                                }
                            }
                        }
                    }
                    .frame(height: 140)
                }
                if network.selectedAppID != nil {
                    Button("Show all apps") { network.selectedAppID = nil }
                }
            }
            Section {
                TextField("Search apps", text: $search)
                ForEach(network.apps.filter { search.isEmpty || $0.app.name.localizedCaseInsensitiveContains(search) }) { usage in
                    Button {
                        network.selectedAppID = network.selectedAppID == usage.id ? nil : usage.id
                    } label: {
                        HStack {
                            Image(nsImage: network.icon(usage.app)).resizable().frame(width: 24, height: 24)
                            Text(usage.app.name).foregroundStyle(.primary)
                            Spacer()
                            Text(NetworkCoordinator.bytes(usage.traffic.total)).monospacedDigit()
                            if network.selectedAppID == usage.id { Image(systemName: "checkmark") }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(usage.app.path)
                }
                if network.apps.isEmpty {
                    Text("No usage recorded").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.network)
    }
}
