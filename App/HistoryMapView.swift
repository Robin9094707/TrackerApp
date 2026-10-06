import SwiftUI
import MapKit

/// Native clustering keeps every report available without thousands of SwiftUI views.
struct HistoryRouteMap: UIViewRepresentable {
    let prepared: PreparedHistory
    let selected: HistoryPoint?
    @Binding var position: MapCameraPosition
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
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "cluster")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "selected")
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.revision != prepared.revision {
            coordinator.revision = prepared.revision
            let wanted = Dictionary(uniqueKeysWithValues: prepared.mapPoints.map { ($0.id, $0) })
            let obsolete = coordinator.reports.keys.filter { wanted[$0] == nil }
            map.removeAnnotations(obsolete.compactMap { coordinator.reports.removeValue(forKey: $0) })
            let added = wanted.values.filter { coordinator.reports[$0.id] == nil }.map { HistoryReportAnnotation(point: $0) }
            for annotation in added { coordinator.reports[annotation.point.id] = annotation }
            map.addAnnotations(added)
            map.removeOverlays(coordinator.routes)
            coordinator.routes = prepared.mapSegments.filter { $0.coordinates.count > 1 }.map { segment in
                let line = HistoryPolyline(coordinates: segment.coordinates, count: segment.coordinates.count)
                line.color = UIColor((segment.points.first?.network ?? "unknown").rjProviderColor)
                return line
            }
            map.addOverlays(coordinator.routes, level: .aboveRoads)
        }
        if coordinator.selection?.point.id != selected?.id {
            if let old = coordinator.selection { map.removeAnnotation(old) }
            if let old = coordinator.accuracy { map.removeOverlay(old) }
            coordinator.selection = selected.map { HistoryReportAnnotation(point: $0, selected: true) }
            coordinator.accuracy = nil
            if let annotation = coordinator.selection { map.addAnnotation(annotation) }
            if let selected, let accuracy = selected.accuracyM, accuracy.isFinite, accuracy > 0 {
                let circle = MKCircle(center: selected.coordinate, radius: min(accuracy, 100_000))
                coordinator.accuracy = circle; map.addOverlay(circle)
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
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 75, left: 45, bottom: 60, right: 45), animated: !reduceMotion)
            }
        }
    }
    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) { uiView.delegate = nil }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: HistoryRouteMap
        var revision: UUID?
        var reports: [String: HistoryReportAnnotation] = [:]
        var routes: [HistoryPolyline] = []
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
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "cluster", for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = .systemBlue
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.displayPriority = .defaultHigh; view.canShowCallout = false
                view.accessibilityLabel = "\(cluster.memberAnnotations.count) Meldungen. Zum Vergrößern auswählen."
                return view
            }
            guard let report = annotation as? HistoryReportAnnotation else { return nil }
            if report.selected {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "selected", for: report) as! MKMarkerAnnotationView
                view.markerTintColor = .systemBlue; view.glyphImage = UIImage(systemName: "location.fill")
                view.displayPriority = .required; view.clusteringIdentifier = nil; view.canShowCallout = false
                view.accessibilityLabel = "Ausgewählt: \(report.title ?? "Meldung")"
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
            mapView.deselectAnnotation(annotation, animated: false)
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? HistoryPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.color.withAlphaComponent(0.8); renderer.lineWidth = 3
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.3); renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

final class HistoryPolyline: MKPolyline { var color = UIColor.systemBlue }
final class HistoryReportAnnotation: NSObject, MKAnnotation {
    let point: HistoryPoint
    let selected: Bool
    var coordinate: CLLocationCoordinate2D { point.coordinate }
    var title: String? { Date(timeIntervalSince1970: TimeInterval(point.timestamp)).rjTimelineText }
    init(point: HistoryPoint, selected: Bool = false) { self.point = point; self.selected = selected }
}
final class ReportAnnotationView: MKAnnotationView {
    private let dot = UIView()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        dot.frame = CGRect(x: 6, y: 6, width: 14, height: 14); dot.layer.cornerRadius = 7
        dot.layer.borderWidth = 2; dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.shadowColor = UIColor.black.cgColor; dot.layer.shadowOpacity = 0.15; dot.layer.shadowRadius = 3
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
