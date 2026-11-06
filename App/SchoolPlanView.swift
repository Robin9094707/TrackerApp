import MapKit
import SwiftUI

struct SchoolPlanPlace: Codable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var kind = "school"
    var lat = 0.0
    var lon = 0.0
    var radius = 120

    enum CodingKeys: String, CodingKey {
        case id, name, kind, lat, lon
        case radius = "radius_m"
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var symbol: String { kind == "school" ? "graduationcap.fill" : kind == "home" ? "house.fill" : "mappin.circle.fill" }
}

struct SchoolPlanRoutine: Codable, Identifiable {
    var id = UUID().uuidString
    var placeID: String
    var days = [1, 2, 3, 4, 5]
    var start = "08:00"
    var end = "13:00"

    enum CodingKeys: String, CodingKey {
        case id, days, start, end
        case placeID = "place_id"
    }
}

struct SchoolPlanSnapshot: Decodable {
    struct Observation: Decodable {
        var placeName: String
        var since: Double
        var last: Double
        enum CodingKeys: String, CodingKey {
            case placeName = "place_name", since = "since_ts", last = "last_in_ts"
        }
    }

    struct Visit: Decodable, Identifiable {
        var placeID: String
        var placeName: String
        var enter: Double
        var leave: Double?
        var last: Double
        var enteredUnknown: Bool
        var id: String { "\(placeID)/\(enter)" }
        enum CodingKeys: String, CodingKey {
            case placeID = "place_id", placeName = "place_name", enter = "enter_ts", leave = "leave_ts"
            case last = "last_in_ts", enteredUnknown = "entered_unknown"
        }
    }

    struct Check: Decodable, Identifiable {
        var id: String
        var placeID: String
        var start: String
        var end: String
        var status: String
        var observedAt: Double?
        enum CodingKeys: String, CodingKey {
            case id, start, end, status
            case placeID = "place_id", observedAt = "arrival_ts"
        }

        var title: String {
            switch status {
            case "confirmed": "Im Zeitfenster geortet"
            case "upcoming": "Steht noch an"
            case "waiting": "Warte auf Standortmeldung"
            default: "Keine Anwesenheit bestätigt"
            }
        }

        var symbol: String {
            switch status {
            case "confirmed": "checkmark.circle.fill"
            case "upcoming": "calendar"
            case "waiting": "clock"
            default: "questionmark.circle"
            }
        }
    }

    struct Fix: Decodable {
        var ts: Double
        var address: String
    }

    var enabled: Bool
    var revision: Int
    var day: String
    var today: String
    var timezone: String
    var places: [SchoolPlanPlace]
    var routines: [SchoolPlanRoutine]
    var location: Fix?
    var current: [Observation]
    var visits: [Visit]
    var checks: [Check]

    var calendar: Calendar { HistoryCalendar.calendar(timezone: timezone) }

    func time(_ timestamp: Double) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: TrackerTimeText.locale, timeZone: calendar.timeZone)
        )
    }
}

private struct SchoolPlanDraft: Encodable {
    var enabled: Bool
    var revision: Int
    var places: [SchoolPlanPlace]
    var routines: [SchoolPlanRoutine]

    init(_ snapshot: SchoolPlanSnapshot) {
        enabled = snapshot.enabled
        revision = snapshot.revision
        places = snapshot.places
        routines = snapshot.routines
    }

    var canSave: Bool {
        routines.allSatisfy { !$0.days.isEmpty && $0.start < $0.end }
    }
}

struct SchoolPlanView: View {
    let tracker: Tracker
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: SchoolPlanSnapshot?
    @State private var requestedDay: String?
    @State private var showEditor = false
    @State private var error: String?
    @State private var requestID = UUID()
    private let path = "/api/mobile/v1/school-plan"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                        Button("Erneut laden", systemImage: "arrow.clockwise") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }.rjCard()
                }
                if let snapshot {
                    statusCard(snapshot)
                    if snapshot.enabled {
                        datePicker(snapshot)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)], spacing: 16) {
                            routineCard(snapshot)
                            visitCard(snapshot)
                        }
                    }
                } else if error == nil {
                    ProgressView("Tagesplan wird geladen …")
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                }
            }.padding(16).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .rjScreenChrome()
        .navigationTitle("Schultasche & Routinen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if snapshot != nil {
                Button("Tagesplan bearbeiten", systemImage: "slider.horizontal.3") { showEditor = true }
                    .accessibilityIdentifier("school-plan-edit")
            }
        }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
            if let snapshot {
                SchoolPlanEditor(tracker: tracker, draft: SchoolPlanDraft(snapshot), timeZone: snapshot.calendar.timeZone, save: save)
            }
        }
        .task(id: requestedDay) { await load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if !showEditor { await load() }
            }
        }
        .refreshable { await load() }
    }

    private func statusCard(_ value: SchoolPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RJSectionTitle(title: tracker.name, subtitle: value.enabled ? "Schultaschenmodus aktiv" : "Schultaschenmodus aus", symbol: "backpack.fill")
            if let current = value.current.first {
                Label(current.placeName, systemImage: "location.circle.fill")
                    .font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor)
                Text("Letzte Meldung dort um \(value.time(current.last))")
                    .foregroundStyle(.secondary)
            } else if value.enabled, value.day == value.today {
                Text("Kein aktueller Aufenthalt bestätigt").font(.headline)
            }
            if value.day == value.today, let location = value.location {
                Label(location.address.isEmpty ? "Letzte Standortmeldung um \(value.time(location.ts))" : "\(location.address) · \(value.time(location.ts))",
                      systemImage: "location").font(.subheadline).foregroundStyle(.secondary)
            }
            Button(value.enabled ? "Orte und Routinen einrichten" : "Schultaschenmodus einrichten", systemImage: "slider.horizontal.3") {
                showEditor = true
            }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, alignment: .leading).rjCard()
    }

    @ViewBuilder private func datePicker(_ value: SchoolPlanSnapshot) -> some View {
        if let today = HistoryCalendar.date(value.today, calendar: value.calendar),
           let earliest = value.calendar.date(byAdding: .day, value: -30, to: today) {
            DatePicker("Tagesübersicht", selection: Binding(
                get: { HistoryCalendar.date(requestedDay ?? value.today, calendar: value.calendar) ?? today },
                set: { date in
                    let day = HistoryCalendar.key(date, calendar: value.calendar)
                    requestedDay = day == value.today ? nil : day
                }
            ), in: earliest...today, displayedComponents: .date)
            .environment(\.timeZone, value.calendar.timeZone)
            .rjCard()
            if value.day != (requestedDay ?? value.today) {
                Label("Tagesübersicht wird aktualisiert …", systemImage: "clock")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func routineCard(_ value: SchoolPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RJSectionTitle(title: "Geplant", subtitle: "Zeitfenster für diesen Tag", symbol: "calendar")
            if value.checks.isEmpty {
                Text("Für diesen Tag ist keine Routine geplant.").foregroundStyle(.secondary)
            }
            ForEach(value.checks) { check in
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.places.first(where: { $0.id == check.placeID })?.name ?? "Ort").font(.headline)
                    Text("\(check.start)–\(check.end) Uhr").monospacedDigit()
                    Label(check.title, systemImage: check.symbol)
                        .font(.subheadline)
                        .foregroundStyle(check.status == "confirmed" ? Color.green : Color.secondary)
                    if let time = check.observedAt {
                        Text("Im Zeitfenster erstmals um \(value.time(time)) gemeldet")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).rjCard()
    }

    private func visitCard(_ value: SchoolPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RJSectionTitle(title: "Aufenthalte", subtitle: "Aus Standortmeldungen ermittelt", symbol: "clock.arrow.circlepath")
            if value.visits.isEmpty {
                Text("Für diesen Tag liegt noch kein bestätigter Aufenthalt vor.").foregroundStyle(.secondary)
            }
            ForEach(value.visits.reversed()) { visit in
                VStack(alignment: .leading, spacing: 4) {
                    Label(visit.placeName, systemImage: value.places.first(where: { $0.id == visit.placeID })?.symbol ?? "mappin")
                        .font(.headline)
                    Text(visit.enteredUnknown ? "Erstmals dort gemeldet um \(value.time(visit.enter))" : "Ankunft gegen \(value.time(visit.enter))")
                    if let leave = visit.leave {
                        Text("Verlassen gegen \(value.time(leave))").foregroundStyle(.secondary)
                    } else {
                        Text("Zuletzt dort gemeldet um \(value.time(visit.last))").foregroundStyle(.secondary)
                    }
                }.font(.subheadline)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).rjCard()
    }

    private var query: [URLQueryItem] {
        [.init(name: "ref", value: tracker.ref)] + (requestedDay.map { [.init(name: "day", value: $0)] } ?? [])
    }

    @MainActor private func load() async {
        let id = UUID()
        requestID = id
        do {
            let value: SchoolPlanSnapshot = try await APIClient.shared.request(path: path, query: query)
            guard requestID == id, !Task.isCancelled else { return }
            snapshot = value
            error = nil
        } catch is CancellationError {
        } catch APIError.http(let code, _) where code == 404 && snapshot == nil {
            if requestID == id { error = "Der Tagesplan benötigt die aktualisierte Serverdatei (Backend 20.7.1) und einen serverseitigen Tracker." }
        } catch {
            if requestID == id { self.error = error.localizedDescription }
        }
    }

    @MainActor private func save(_ draft: SchoolPlanDraft) async throws {
        let data = try JSONEncoder().encode(draft)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.message("Der Tagesplan konnte nicht vorbereitet werden.")
        }
        requestID = UUID()
        let updated: SchoolPlanSnapshot = try await APIClient.shared.request(path: path, method: "PUT", json: json, query: query)
        snapshot = updated
        error = nil
    }
}

private struct SchoolPlanEditor: View {
    let tracker: Tracker
    @State var draft: SchoolPlanDraft
    let timeZone: TimeZone
    let save: (SchoolPlanDraft) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingPlace: SchoolPlanPlace?
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Schultaschenmodus aktiv", isOn: $draft.enabled)
                        .accessibilityIdentifier("school-plan-enabled")
                } footer: {
                    Text("Die Orte und Routinen gelten für \(tracker.name). Die Anzeige beruht auf Meldungen des Trackers.")
                }
                Section("Orte") {
                    ForEach(draft.places) { place in
                        Button { editingPlace = place } label: {
                            Label(place.name, systemImage: place.symbol)
                        }
                    }.onDelete { offsets in
                        let ids = Set(offsets.map { draft.places[$0].id })
                        draft.places.remove(atOffsets: offsets)
                        draft.routines.removeAll { ids.contains($0.placeID) }
                    }
                    Button("Ort hinzufügen", systemImage: "plus.circle") {
                        let seed = tracker.validLocation
                        editingPlace = SchoolPlanPlace(kind: draft.places.contains { $0.kind == "school" } ? "home" : "school",
                                                       lat: seed?.latitude ?? 51.43, lon: seed?.longitude ?? 6.76)
                    }.disabled(draft.places.count >= 20)
                }
                Section {
                    ForEach($draft.routines) { $routine in
                        NavigationLink {
                            SchoolRoutineEditor(routine: $routine, places: draft.places, timeZone: timeZone)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(draft.places.first(where: { $0.id == routine.placeID })?.name ?? "Ort auswählen")
                                Text("\(routine.start)–\(routine.end) Uhr · \(routine.days.count) Wochentage")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { draft.routines.remove(atOffsets: $0) }
                    Button("Routine hinzufügen", systemImage: "plus.circle") {
                        if let place = draft.places.first {
                            draft.routines.append(SchoolPlanRoutine(placeID: place.id))
                        }
                    }.disabled(draft.places.isEmpty || draft.routines.count >= 40)
                } header: {
                    Text("Wöchentliche Routinen")
                } footer: {
                    Text(draft.places.isEmpty ? "Lege zuerst einen Ort an." : "Tippe auf eine Routine, um Ort, Wochentage und Zeiten festzulegen. Beim Löschen eines Orts entfallen auch seine Routinen.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !draft.canSave {
                    Section { Text("Für jede Routine muss mindestens ein Wochentag gewählt sein und das Ende nach dem Beginn liegen.").foregroundStyle(.secondary) }
                }
            }
            .rjFormChrome()
            .navigationTitle("Tagesplan bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Speichert …" : "Sichern") {
                        Task {
                            saving = true
                            defer { saving = false }
                            do { try await save(draft); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(!draft.canSave || saving)
                }
            }
            .sheet(item: $editingPlace) { place in
                SchoolPlaceEditor(place: place) { updated in
                    if let index = draft.places.firstIndex(where: { $0.id == updated.id }) {
                        draft.places[index] = updated
                    } else { draft.places.append(updated) }
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }
}

private struct SchoolRoutineEditor: View {
    @Binding var routine: SchoolPlanRoutine
    let places: [SchoolPlanPlace]
    let timeZone: TimeZone

    var body: some View {
        Form {
            Picker("Ort", selection: $routine.placeID) {
                ForEach(places) { Text($0.name).tag($0.id) }
            }
            Section("Zeitfenster") {
                DatePicker("Von", selection: time($routine.start), displayedComponents: .hourAndMinute)
                DatePicker("Bis", selection: time($routine.end), displayedComponents: .hourAndMinute)
            }
            Section("Wochentage") {
                ForEach(Array(["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"].enumerated()), id: \.offset) { index, name in
                    Toggle(name, isOn: Binding(get: { routine.days.contains(index + 1) }, set: { selected in
                        if selected { routine.days = Array(Set(routine.days + [index + 1])).sorted() }
                        else { routine.days.removeAll { $0 == index + 1 } }
                    }))
                }
            }
        }
        .environment(\.timeZone, timeZone)
        .rjFormChrome().navigationTitle("Routine")
    }

    private func time(_ clock: Binding<String>) -> Binding<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return Binding(get: {
            let parts = clock.wrappedValue.split(separator: ":").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: parts.first ?? 8, minute: parts.last ?? 0)) ?? .now
        }, set: {
            let parts = calendar.dateComponents([.hour, .minute], from: $0)
            clock.wrappedValue = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        })
    }
}

private struct SchoolPlaceEditor: View {
    @State var place: SchoolPlanPlace
    let save: (SchoolPlanPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var searchError: String?
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ort") {
                    Picker("Kategorie", selection: $place.kind) {
                        Text("Schule").tag("school")
                        Text("Zuhause").tag("home")
                        Text("Anderer Ort").tag("other")
                    }
                    TextField("Name des Orts", text: $place.name)
                    HStack {
                        TextField("Adresse oder Ort suchen", text: $query)
                            .submitLabel(.search).onSubmit { Task { await search() } }
                        Button("Suchen", systemImage: "magnifyingglass") { Task { await search() } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(searching || query.isEmpty)
                    }
                    ForEach(results.indices, id: \.self) { index in
                        let item = results[index]
                        Button {
                            let coordinate = item.placemark.coordinate
                            place.lat = coordinate.latitude
                            place.lon = coordinate.longitude
                            if place.name.isEmpty { place.name = item.name ?? "" }
                            focusMap()
                            results = []
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "Ort")
                                if let detail = item.placemark.title {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if searching { ProgressView("Suche läuft …") }
                    if let searchError { Text(searchError).font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    Map(position: $camera, interactionModes: [.pan, .zoom]) {
                        MapCircle(center: place.coordinate, radius: Double(place.radius))
                            .foregroundStyle(.blue.opacity(0.16)).stroke(.blue, lineWidth: 2)
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        if camera.positionedByUser {
                            place.lat = context.region.center.latitude
                            place.lon = context.region.center.longitude
                        }
                    }
                    .overlay {
                        Image(systemName: "scope").font(.title2.bold()).foregroundStyle(.blue)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 230)
                    .accessibilityLabel("Karte zur Wahl des Orts")
                    Stepper("Radius: \(place.radius) m", value: $place.radius, in: 30...2000, step: 10)
                } footer: {
                    Text("Verschiebe die Karte, bis das Fadenkreuz in der Mitte des gewünschten Orts liegt.")
                }
            }
            .rjFormChrome().navigationTitle("Ort festlegen").navigationBarTitleDisplayMode(.inline)
            .onAppear { focusMap() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        if place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            place.name = place.kind == "school" ? "Schule" : place.kind == "home" ? "Zuhause" : "Neuer Ort"
                        }
                        save(place)
                        dismiss()
                    }
                }
            }
        }
    }

    private func focusMap() {
        camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))
    }

    @MainActor private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true
        searchError = nil
        results = []
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = Array(response.mapItems.prefix(5))
            if results.isEmpty { searchError = "Kein Ort gefunden." }
        } catch { searchError = "Die Ortssuche konnte nicht abgeschlossen werden." }
    }
}
