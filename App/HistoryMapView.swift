import SwiftUI
import MapKit

/// A camera request is consumed once per map. Map gestures never write back to it.
struct HistoryMapCameraRequest {
    enum Target {
        case overview
        case focus(CLLocationCoordinate2D, meters: Double)
    }

    let id = UUID()
    var target: Target = .overview

    static func bounds(for coordinates: [CLLocationCoordinate2D], minimumMeters: Double = 650) -> MKMapRect? {
        let coordinates = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard let first = coordinates.first else { return nil }
        let origin = MKMapPoint(first)
        let world = MKMapRect.world.size.width
        var minX = origin.x, maxX = origin.x, minY = origin.y, maxY = origin.y
        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            let x = origin.x + (point.x - origin.x).remainder(dividingBy: world)
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let latitude = MKMapPoint(x: origin.x, y: (minY + maxY) / 2).coordinate.latitude
        let minimum = minimumMeters * MKMapPointsPerMeterAtLatitude(latitude)
        let width = min(world, max(maxX - minX, minimum))
        let height = min(world, max(maxY - minY, minimum))
        return MKMapRect(x: (minX + maxX - width) / 2, y: (minY + maxY - height) / 2, width: width, height: height)
    }

    static func focus(_ coordinate: CLLocationCoordinate2D, accuracy: Double?, minimum: Double = 950) -> Target {
        let radius = accuracy.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 100
        return .focus(coordinate, meters: min(18_000, max(minimum, radius * 5)))
    }
}

/// Native clustering keeps every report available without thousands of SwiftUI views.
struct HistoryRouteMap: UIViewRepresentable {
    let prepared: PreparedHistory
    let selected: HistoryPoint?
    let camera: HistoryMapCameraRequest
    var revealThrough: Int?
    var satellite = false
    let onSelect: (HistoryPoint) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MapContainer {
        let container = MapContainer(frame: .zero)
        let map = container.map
        let coordinator = context.coordinator
        container.didLayout = { [weak coordinator] map in coordinator?.applyCamera(to: map) }
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true; map.showsScale = true
        map.register(ReportAnnotationView.self, forAnnotationViewWithReuseIdentifier: "report")
        map.register(HistoryClusterView.self, forAnnotationViewWithReuseIdentifier: "cluster")
        map.register(SelectedReportView.self, forAnnotationViewWithReuseIdentifier: "selected")
        map.register(EndpointAnnotationView.self, forAnnotationViewWithReuseIdentifier: "endpoint")
        return container
    }
    func updateUIView(_ container: MapContainer, context: Context) {
        let map = container.map
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.satellite != satellite {
            coordinator.satellite = satellite
            map.preferredConfiguration = satellite ? MKHybridMapConfiguration(elevationStyle: .flat) : MKStandardMapConfiguration(elevationStyle: .flat)
        }
        if coordinator.revision != prepared.revision {
            coordinator.revision = prepared.revision
            let wanted = Dictionary(uniqueKeysWithValues: prepared.mapPoints.map { ($0.id, $0) })
            let obsolete = coordinator.reports.keys.filter { wanted[$0] == nil }
            map.removeAnnotations(obsolete.compactMap { coordinator.reports.removeValue(forKey: $0) })
            let added = wanted.values.filter { coordinator.reports[$0.id] == nil }.map { HistoryReportAnnotation(point: $0) }
            for annotation in added { coordinator.reports[annotation.point.id] = annotation }
            map.addAnnotations(added)
            map.removeOverlays(coordinator.routes + coordinator.casings)
            let first = Double(prepared.points.first?.timestamp ?? 0)
            let span = max(1, Double(prepared.points.last?.timestamp ?? 0) - first)
            let segments = prepared.mapSegments.filter { $0.coordinates.count > 1 }
            coordinator.casings = segments.map { segment in
                let casing = HistoryPolyline(coordinates: segment.coordinates, count: segment.coordinates.count)
                casing.casing = true
                return casing
            }
            coordinator.routes = segments.map { segment in
                let line = HistoryPolyline(coordinates: segment.coordinates, count: segment.coordinates.count)
                line.fractions = segment.points.map { (Double($0.timestamp) - first) / span }
                line.progress = prepared.mapProgress[segment.id]
                return line
            }
            map.addOverlays(coordinator.casings, level: .aboveRoads)
            map.addOverlays(coordinator.routes, level: .aboveRoads)
            map.removeAnnotations(coordinator.endpoints)
            coordinator.endpoints = []
            if let start = prepared.points.first, let end = prepared.points.last {
                coordinator.endpoints.append(HistoryEndpointAnnotation(point: start, kind: .start))
                if end.id != start.id { coordinator.endpoints.append(HistoryEndpointAnnotation(point: end, kind: .end)) }
            }
            map.addAnnotations(coordinator.endpoints)
        }
        if coordinator.selection?.point.id != selected?.id {
            if let old = coordinator.selection { map.removeAnnotation(old) }
            if let old = coordinator.accuracy { map.removeOverlay(old) }
            coordinator.selection = selected.map { HistoryReportAnnotation(point: $0, selected: true) }
            coordinator.accuracy = nil
            if let annotation = coordinator.selection { map.addAnnotation(annotation) }
            if let selected, let accuracy = selected.accuracyM, accuracy.isFinite, accuracy > 0 {
                let circle = MKCircle(center: selected.coordinate, radius: min(accuracy, 100_000))
                coordinator.accuracy = circle; map.addOverlay(circle, level: .aboveRoads)
            }
        }
        coordinator.updateProgress(on: map)
        coordinator.applyCamera(to: map)
    }

    static func dismantleUIView(_ container: MapContainer, coordinator: Coordinator) {
        container.didLayout = nil
        container.map.delegate = nil
    }

    final class MapContainer: UIView {
        let map = MKMapView()
        var didLayout: ((MKMapView) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(map)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            map.frame = bounds
            didLayout?(map)
        }
    }

    /// Older reports are cool and pale, the newest are saturated, like a fading trail.
    static func trailColor(_ fraction: Double) -> UIColor {
        let stops: [(Double, UIColor)] = [(0, .systemTeal), (0.55, .systemBlue), (1, .systemIndigo)]
        let t = min(max(fraction, 0), 1)
        guard let upper = stops.firstIndex(where: { $0.0 >= t }), upper > 0 else { return stops[0].1 }
        let (a, colorA) = stops[upper - 1]; let (b, colorB) = stops[upper]
        let local = CGFloat((t - a) / max(b - a, 0.0001))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        colorA.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); colorB.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * local, green: g1 + (g2 - g1) * local, blue: b1 + (b2 - b1) * local, alpha: 1)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: HistoryRouteMap
        var revision: UUID?
        var satellite = false
        var reports: [String: HistoryReportAnnotation] = [:]
        var routes: [HistoryPolyline] = []
        var casings: [HistoryPolyline] = []
        var endpoints: [HistoryEndpointAnnotation] = []
        var selection: HistoryReportAnnotation?
        var accuracy: MKCircle?
        private var appliedCamera: UUID?
        private var revealedTimestamp: Int?
        init(_ parent: HistoryRouteMap) { self.parent = parent }

        func applyCamera(to map: MKMapView) {
            guard appliedCamera != parent.camera.id, map.bounds.width > 1, map.bounds.height > 1 else { return }
            let rect: MKMapRect?
            switch parent.camera.target {
            case .overview:
                rect = HistoryMapCameraRequest.bounds(for: parent.prepared.points.map(\.coordinate))
            case let .focus(coordinate, meters):
                rect = HistoryMapCameraRequest.bounds(for: [coordinate], minimumMeters: meters)
            }
            guard let rect else { return }
            let animated = appliedCamera != nil && !parent.reduceMotion
            appliedCamera = parent.camera.id
            fit(rect, on: map, animated: animated)
        }

        private func fit(_ rect: MKMapRect, on map: MKMapView, animated: Bool) {
            let horizontal = min(56, map.bounds.width * 0.16)
            let vertical = min(56, map.bounds.height * 0.19)
            map.setVisibleMapRect(rect, edgePadding: .init(top: vertical, left: horizontal, bottom: vertical, right: horizontal), animated: animated)
        }

        func updateProgress(on map: MKMapView) {
            guard revealedTimestamp != parent.revealThrough else { return }
            revealedTimestamp = parent.revealThrough
            for line in routes {
                if let renderer = map.renderer(for: line) as? MKGradientPolylineRenderer {
                    renderer.strokeEnd = line.strokeEnd(at: revealedTimestamp)
                }
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "cluster", for: cluster) as! HistoryClusterView
                view.configure(count: cluster.memberAnnotations.count)
                return view
            }
            if let endpoint = annotation as? HistoryEndpointAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "endpoint", for: endpoint) as! EndpointAnnotationView
                view.configure(endpoint)
                return view
            }
            guard let report = annotation as? HistoryReportAnnotation else { return nil }
            if report.selected {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "selected", for: report) as! SelectedReportView
                view.configure(report)
                return view
            }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "report", for: report) as! ReportAnnotationView
            view.configure(report)
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                let members = cluster.memberAnnotations.compactMap { $0 as? HistoryReportAnnotation }
                if let latest = members.max(by: { $0.point.timestamp < $1.point.timestamp }) {
                    let location = CLLocation(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude)
                    let spread = members.contains {
                        location.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) > 12
                    }
                    if spread, let rect = HistoryMapCameraRequest.bounds(for: members.map(\.coordinate), minimumMeters: 70) {
                        // At the closest useful scale, tapping again selects a report.
                        if mapView.visibleMapRect.size.width > rect.size.width * 2 {
                            fit(rect, on: mapView, animated: !parent.reduceMotion)
                        } else { parent.onSelect(latest.point) }
                    } else { parent.onSelect(latest.point) }
                }
            } else if let report = annotation as? HistoryReportAnnotation { parent.onSelect(report.point) }
            else if let endpoint = annotation as? HistoryEndpointAnnotation { parent.onSelect(endpoint.point) }
            mapView.deselectAnnotation(annotation, animated: false)
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? HistoryPolyline {
                if line.casing {
                    let renderer = MKPolylineRenderer(polyline: line)
                    renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.26)
                    renderer.lineWidth = 8; renderer.lineCap = .round; renderer.lineJoin = .round
                    return renderer
                }
                let renderer = MKGradientPolylineRenderer(polyline: line)
                let count = max(line.fractions.count, 2)
                let fractions = line.fractions.isEmpty ? [0, 1] : line.fractions
                renderer.setColors(fractions.map(HistoryRouteMap.trailColor),
                                   locations: (0..<fractions.count).map { CGFloat($0) / CGFloat(max(count - 1, 1)) })
                renderer.strokeEnd = line.strokeEnd(at: parent.revealThrough)
                renderer.lineWidth = 5; renderer.lineCap = .round; renderer.lineJoin = .round
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.10)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.35); renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

final class HistoryPolyline: MKPolyline {
    var fractions: [Double] = []
    var casing = false
    var progress: HistoryRouteProgress?

    func strokeEnd(at timestamp: Int?) -> CGFloat {
        guard let timestamp, let progress else { return 1 }
        return CGFloat(progress.fraction(at: timestamp))
    }
}
final class HistoryReportAnnotation: NSObject, MKAnnotation {
    let point: HistoryPoint
    let selected: Bool
    var coordinate: CLLocationCoordinate2D { point.coordinate }
    var title: String? { Date(timeIntervalSince1970: TimeInterval(point.timestamp)).rjTimelineText }
    init(point: HistoryPoint, selected: Bool = false) { self.point = point; self.selected = selected }
}
final class HistoryEndpointAnnotation: NSObject, MKAnnotation {
    enum Kind { case start, end }
    let point: HistoryPoint
    let kind: Kind
    var coordinate: CLLocationCoordinate2D { point.coordinate }
    var title: String? { kind == .start ? "Beginn" : "Zuletzt" }
    init(point: HistoryPoint, kind: Kind) { self.point = point; self.kind = kind }
}

final class ReportAnnotationView: MKAnnotationView {
    private let dot = UIView()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        dot.frame = CGRect(x: 5, y: 5, width: 12, height: 12); dot.layer.cornerRadius = 6
        dot.layer.borderWidth = 2; dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.shadowColor = UIColor.black.cgColor; dot.layer.shadowOpacity = 0.18; dot.layer.shadowRadius = 2; dot.layer.shadowOffset = .init(width: 0, height: 1)
        addSubview(dot); canShowCallout = false; collisionMode = .circle
        clusteringIdentifier = "history-reports"; displayPriority = .defaultLow
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ report: HistoryReportAnnotation) {
        annotation = report
        dot.backgroundColor = UIColor((report.point.network ?? "unknown").rjProviderColor)
        accessibilityLabel = "\((report.point.network ?? "unknown").rjProviderName), \(report.title ?? "Meldung")"
    }
}

/// Count bubble in the Find My style instead of a stock marker balloon.
final class HistoryClusterView: MKAnnotationView {
    private let label = UILabel()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        backgroundColor = .systemBlue
        layer.cornerRadius = 17; layer.borderWidth = 2.5; layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.2; layer.shadowRadius = 4; layer.shadowOffset = .init(width: 0, height: 2)
        label.frame = bounds; label.textAlignment = .center; label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .bold); label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.6
        addSubview(label); canShowCallout = false; displayPriority = .defaultHigh; collisionMode = .circle
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(count: Int) {
        let size: CGFloat = count >= 100 ? 42 : count >= 10 ? 38 : 34
        frame.size = CGSize(width: size, height: size); layer.cornerRadius = size / 2; label.frame = bounds
        label.text = "\(count)"
        accessibilityLabel = "\(count) Meldungen. Zum Vergrößern auswählen."
    }
}

final class SelectedReportView: MKAnnotationView {
    private let halo = UIView()
    private let core = UIView()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        halo.frame = bounds; halo.layer.cornerRadius = 22; halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.22)
        core.frame = CGRect(x: 12, y: 12, width: 20, height: 20); core.layer.cornerRadius = 10
        core.backgroundColor = .systemBlue; core.layer.borderWidth = 3.5; core.layer.borderColor = UIColor.white.cgColor
        core.layer.shadowColor = UIColor.black.cgColor; core.layer.shadowOpacity = 0.25; core.layer.shadowRadius = 4; core.layer.shadowOffset = .init(width: 0, height: 2)
        addSubview(halo); addSubview(core)
        displayPriority = .required; clusteringIdentifier = nil; canShowCallout = false; zPriority = .max
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ report: HistoryReportAnnotation) {
        annotation = report
        accessibilityLabel = "Ausgewählt: \(report.title ?? "Meldung")"
        halo.layer.removeAllAnimations()
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.55; pulse.toValue = 1.15; pulse.duration = 1.4
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        halo.layer.add(pulse, forKey: "pulse")
    }
    override func prepareForReuse() { super.prepareForReuse(); halo.layer.removeAllAnimations() }
}

final class EndpointAnnotationView: MKAnnotationView {
    private let badge = UIImageView()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        layer.cornerRadius = 14; layer.borderWidth = 2.5; layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.22; layer.shadowRadius = 3; layer.shadowOffset = .init(width: 0, height: 1.5)
        badge.frame = bounds.insetBy(dx: 7, dy: 7); badge.contentMode = .scaleAspectFit; badge.tintColor = .white
        addSubview(badge); canShowCallout = false; displayPriority = .required; clusteringIdentifier = nil
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ endpoint: HistoryEndpointAnnotation) {
        annotation = endpoint
        backgroundColor = endpoint.kind == .start ? .systemGreen : .systemIndigo
        badge.image = UIImage(systemName: endpoint.kind == .start ? "flag.fill" : "flag.checkered", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        accessibilityLabel = "\(endpoint.title ?? ""), \(Date(timeIntervalSince1970: TimeInterval(endpoint.point.timestamp)).rjTimelineText)"
    }
}
