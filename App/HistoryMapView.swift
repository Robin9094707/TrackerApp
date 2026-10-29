import SwiftUI
import MapKit

/// Native clustering keeps every report available without thousands of SwiftUI views.
struct HistoryRouteMap: UIViewRepresentable {
    let prepared: PreparedHistory
    let selected: HistoryPoint?
    @Binding var position: MapCameraPosition
    var satellite = false
    var bottomInset: CGFloat = 60
    let onSelect: (HistoryPoint) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true; map.showsScale = true
        map.register(ReportAnnotationView.self, forAnnotationViewWithReuseIdentifier: "report")
        map.register(HistoryClusterView.self, forAnnotationViewWithReuseIdentifier: "cluster")
        map.register(SelectedReportView.self, forAnnotationViewWithReuseIdentifier: "selected")
        map.register(EndpointAnnotationView.self, forAnnotationViewWithReuseIdentifier: "endpoint")
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
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
        if let region = position.region {
            let signature = Coordinator.signature(region)
            if coordinator.cameraSignature != signature {
                coordinator.cameraSignature = signature
                map.setRegion(region, animated: !reduceMotion)
            }
        } else if coordinator.cameraSignature != "automatic" {
            coordinator.cameraSignature = "automatic"
            var rect = MKMapRect.null
            for point in prepared.points {
                let coordinate = MKMapPoint(point.coordinate)
                rect = rect.union(MKMapRect(x: coordinate.x, y: coordinate.y, width: 1, height: 1))
            }
            if !rect.isNull {
                if rect.width < 600 && rect.height < 600 { rect = rect.insetBy(dx: -700, dy: -700) }
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 48, bottom: bottomInset, right: 48), animated: !reduceMotion)
            }
        }
    }
    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) { uiView.delegate = nil }

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
        var cameraSignature = ""
        init(_ parent: HistoryRouteMap) { self.parent = parent }
        static func signature(_ region: MKCoordinateRegion) -> String {
            "\(region.center.latitude)|\(region.center.longitude)|\(region.span.latitudeDelta)|\(region.span.longitudeDelta)"
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let signature = Self.signature(region)
            cameraSignature = signature
            DispatchQueue.main.async { [weak self] in
                guard let self, self.cameraSignature == signature else { return }
                self.parent.position = .region(region)
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
                var rect = MKMapRect.null
                for member in cluster.memberAnnotations {
                    let p = MKMapPoint(member.coordinate)
                    rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
                }
                if rect.width < 2 && rect.height < 2 {
                    if let report = cluster.memberAnnotations.compactMap({ $0 as? HistoryReportAnnotation }).max(by: { $0.point.timestamp < $1.point.timestamp }) {
                        parent.onSelect(report.point)
                    }
                } else { mapView.setVisibleMapRect(rect, edgePadding: .init(top: 70, left: 55, bottom: 70, right: 55), animated: !parent.reduceMotion) }
            } else if let report = annotation as? HistoryReportAnnotation { parent.onSelect(report.point) }
            else if let endpoint = annotation as? HistoryEndpointAnnotation { parent.onSelect(endpoint.point) }
            mapView.deselectAnnotation(annotation, animated: false)
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? HistoryPolyline {
                if line.casing {
                    let renderer = MKPolylineRenderer(polyline: line)
                    renderer.strokeColor = UIColor.white.withAlphaComponent(0.9)
                    renderer.lineWidth = 8; renderer.lineCap = .round; renderer.lineJoin = .round
                    return renderer
                }
                let renderer = MKGradientPolylineRenderer(polyline: line)
                let count = max(line.fractions.count, 2)
                let fractions = line.fractions.isEmpty ? [0, 1] : line.fractions
                renderer.setColors(fractions.map(HistoryRouteMap.trailColor),
                                   locations: (0..<fractions.count).map { CGFloat($0) / CGFloat(max(count - 1, 1)) })
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
