//
//  MapView.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import LUI
import MapKit
import SwiftUI

/// The identifier for our custom MarkerAnnotationView
let reuseIdentifier = "trackerAnnotation"
let regularDateLabelTag = 9721
let strokedDateLabelTag = 9722

/// SwiftUI wrapper for MKMapView
struct MapView: UIViewRepresentable {
    /// The annotations (locations) to show on the map
    var annotations: [MapAnnotation]

    let showRadii: Bool

    /// The annotations (locations) currently shown on the map. This is used to determine if the view should be refreshed.
    @State var oldAnnotations: [MapAnnotation] = []

    /// The locations of the tracker, sorted by time. This is used to connect the annotations with lines.
    var connections: [CLLocationCoordinate2D]

    /// Determines if the title labels of the annotations should be shown
    @State var showAnnotationLabels = true

    /// Determines if the map has finished loading
    @Binding var mapFinishedLoading: Bool

    /// Adds the polyline and circle overlays to the given mapview.
    func setUpOverlays(onView: MKMapView) {
        /// Add the polyline (connections)
        /// we need to set up all polylines separately. This is due to a glitch which occurs whenever one line within a single polyline is drawn twice
        for index in connections.indices {
            /// To not get an out of bounds exception
            if index != connections.indices.last {
                /// The coordinates to connect.
                let coord1 = connections[index]
                let coord2 = connections[index + 1]

                let connection = [coord1, coord2]

                /// Draw polyline between both coordinates.
                let polyline = MKPolyline(coordinates: connection, count: 2)
                onView.addOverlay(polyline)
            }
        }

        if showRadii {
            /// Add the circles. This shows the user that the locations might not be 100% precise.
            for annotation in annotations {
                let center = annotation.coordinate

                /// The radius is the minimum accuracy. This makes sure that the actual location is somewhere in the circle.
                let circle = MKCircle(center: center, radius: annotation.accuracy)
                onView.addOverlay(circle)
            }
        }
    }

    /// Creates the `MKMapView`
    func makeUIView(context: Context) -> MKMapView {
        /// Set `locationsCount` to initial value.
        DispatchQueue.main.async {
            oldAnnotations = annotations
        }

        /// Create the new map view.
        let view = MKMapView()

        /// Set the delegate
        view.delegate = context.coordinator

        /// Move annotations up
        view.layoutMargins.top = -40

        /// Add the overlays to the map
        setUpOverlays(onView: view)

        /// Add the annotations and put them in focus
        view.addAnnotations(annotations)
        zoomToAnnotations(annotations: annotations, inMapView: view, withAnimation: false)

        /// Hide the map - we will show it after it has been loaded
        view.layer.opacity = 0

        return view
    }

    func zoomToAnnotations(annotations: [MKAnnotation], inMapView mapView: MKMapView, withAnimation: Bool) {
        DispatchQueue.main.async {
            mapView.fit(
                annotations: annotations,
                edgePadding: UIEdgeInsets(top: 20, left: 50, bottom: 50, right: 50),
                animated: withAnimation
            )
        }
    }

    /// Creates the coordinator for `MKMapView`
    func makeCoordinator() -> Coordinator {
        MapView.Coordinator(parent: self)
    }

    /// Updates the `MKMapView`
    func updateUIView(_ uiView: MKMapView, context _: Context) {
        /// We received new location data. Otherwise, we do not need to refresh
        if annotations != oldAnnotations {
            /// Remove all annotations and overlays
            uiView.removeAnnotations(uiView.annotations)
            uiView.removeOverlays(uiView.overlays)

            /// Create the new overlays
            setUpOverlays(onView: uiView)

            /// Add the annotations and put them in focus
            uiView.addAnnotations(annotations)
            zoomToAnnotations(annotations: annotations, inMapView: uiView, withAnimation: true)

            /// Update `oldAnnotations`
            DispatchQueue.main.async {
                oldAnnotations = annotations
            }
        }
    }

    /// The coordinator for `MKMapView`
    class Coordinator: NSObject, MKMapViewDelegate {
        /// The color for the annotations and overlays
        let primaryColor = UIColor(Color.blue)

        /// Reference to the MapView.
        var parent: MapView

        /// Initialize the coordinator
        init(parent: MapView) {
            /// Set the parent
            self.parent = parent
        }

        /// Creates the view for individual annotations.
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            /// Regular/single annotation
            if let mapAnnotation = annotation as? MapAnnotation {
                /// Create the view for the annotation and set the color
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MarkerAnnotationView
                    ?? MarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)

                view.annotation = annotation
                view.displayPriority = .required
                view.collisionMode = .circle
                view.clusteringIdentifier = nil
                view.canShowCallout = false

                let size: CGFloat = 25
                let locationdot = UIImage(systemName: "location.circle.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal).resized(to: CGSize(width: size, height: size))
                view.image = locationdot
                view.centerOffset = .zero
                configureDateLabel(on: view, text: parent.showAnnotationLabels ? mapAnnotation.title : nil)

                return view
            }

            return nil
        }

        /// Creates the view for overlays.
        func mapView(_: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            /// Creates the view for the polyline.
            if let polyline = overlay as? MKPolyline {
                let lineRenderer = MKPolylineRenderer(polyline: polyline)
                lineRenderer.strokeColor = primaryColor
                lineRenderer.lineWidth = 2.2
                lineRenderer.lineDashPattern = [NSNumber(value: 6), NSNumber(value: 3)]
                lineRenderer.lineDashPhase = 0
                lineRenderer.lineCap = .butt
                lineRenderer.lineJoin = .round

                return lineRenderer
            }

            /// Creates the view for circles.
            if let circle = overlay as? MKCircle {
                let circleRenderer = MKCircleRenderer(overlay: circle)
                circleRenderer.fillColor = primaryColor.withAlphaComponent(0.2)
                circleRenderer.strokeColor = UIColor.clear
                circleRenderer.lineWidth = 2
                return circleRenderer
            }

            /// Fallback - default
            return MKOverlayRenderer(overlay: overlay)
        }

        /// The map finished loading
        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            /// Make the map visible
            UIView.animate(withDuration: 0.2) {
                mapView.layer.opacity = 1
            }

            parent.mapFinishedLoading = true

            updateDateLabelVisibility(in: mapView)
        }

        func mapView(_ mapView: MKMapView, didAdd _: [MKAnnotationView]) {
            updateDateLabelVisibility(in: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            updateDateLabelVisibility(in: mapView)
        }

        private func configureDateLabel(on view: MKAnnotationView, text: String?) {
            let font = UIFont.systemFont(ofSize: 12, weight: .bold)

            let makeLabel: (Int) -> UILabel = { tag in
                let newLabel = UILabel()
                newLabel.tag = tag
                newLabel.translatesAutoresizingMaskIntoConstraints = false
                newLabel.backgroundColor = .clear
                newLabel.font = font
                newLabel.textAlignment = .center
                newLabel.numberOfLines = 2
                newLabel.lineBreakMode = .byWordWrapping
                newLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
                newLabel.setContentHuggingPriority(.required, for: .horizontal)

                view.addSubview(newLabel)
                NSLayoutConstraint.activate([
                    newLabel.topAnchor.constraint(equalTo: view.bottomAnchor, constant: 2),
                    newLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    newLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
                ])
                return newLabel
            }

            view.clipsToBounds = false
            let regularLabel = (view.viewWithTag(regularDateLabelTag) as? UILabel) ?? makeLabel(regularDateLabelTag)
            let strokedLabel = (view.viewWithTag(strokedDateLabelTag) as? UILabel) ?? makeLabel(strokedDateLabelTag)
            view.sendSubviewToBack(strokedLabel)
            view.bringSubviewToFront(regularLabel)

            let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = !(trimmedText?.isEmpty ?? true)

            regularLabel.isHidden = !hasText
            strokedLabel.isHidden = !hasText
            if hasText {
                let displayText = multilineLabelText(from: trimmedText!)
                let regularTextColor = UIColor(.mainColor)
                let strokeColor = UIColor { traits in
                    traits.userInterfaceStyle == .dark ? .black.withAlphaComponent(0.3) : .white.withAlphaComponent(0.7)
                }

                regularLabel.textColor = regularTextColor
                regularLabel.text = displayText

                strokedLabel.attributedText = NSAttributedString(
                    string: displayText,
                    attributes: [
                        .foregroundColor: UIColor.clear,
                        .strokeColor: strokeColor,
                        .strokeWidth: 25.0,
                        .font: font,
                    ]
                )
            } else {
                regularLabel.text = nil
                strokedLabel.attributedText = nil
            }
        }

        private func multilineLabelText(from text: String) -> String {
            let parts = text.components(separatedBy: " - ")
            guard parts.count == 2 else { return text }
            return parts[0] + " -\n" + parts[1]
        }

        private func updateDateLabelVisibility(in mapView: MKMapView) {
            struct LabelCandidate {
                let regularLabel: UILabel
                let strokedLabel: UILabel
                let frame: CGRect
                let distanceToCenter: CGFloat
            }

            let mapCenter = CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY)
            var candidates = [LabelCandidate]()

            for annotation in mapView.annotations {
                guard annotation is MapAnnotation else { continue }
                guard let annotationView = mapView.view(for: annotation) else { continue }
                guard let regularLabel = annotationView.viewWithTag(regularDateLabelTag) as? UILabel else { continue }
                guard let strokedLabel = annotationView.viewWithTag(strokedDateLabelTag) as? UILabel else { continue }
                guard let text = regularLabel.text, !text.isEmpty else { continue }

                regularLabel.isHidden = false
                strokedLabel.isHidden = false

                let frameInMap = regularLabel.convert(regularLabel.bounds, to: mapView).insetBy(dx: -2, dy: -1)
                let center = CGPoint(x: frameInMap.midX, y: frameInMap.midY)
                let distance = hypot(center.x - mapCenter.x, center.y - mapCenter.y)

                candidates.append(
                    LabelCandidate(
                        regularLabel: regularLabel,
                        strokedLabel: strokedLabel,
                        frame: frameInMap,
                        distanceToCenter: distance
                    )
                )
            }

            candidates.sort { $0.distanceToCenter < $1.distanceToCenter }

            var occupiedFrames = [CGRect]()
            for candidate in candidates {
                if occupiedFrames.contains(where: { $0.intersects(candidate.frame) }) {
                    candidate.regularLabel.isHidden = true
                    candidate.strokedLabel.isHidden = true
                } else {
                    occupiedFrames.append(candidate.frame)
                }
            }
        }
    }
}

/// Disables MKMapKit clustering
final class MarkerAnnotationView: MKAnnotationView {
    override var annotation: MKAnnotation? {
        willSet {
            /// Disables clustering of pins
            displayPriority = MKFeatureDisplayPriority.required
            collisionMode = .circle
            clusteringIdentifier = nil
            canShowCallout = false
        }
    }
}

extension MKMapView {
    func fit(annotations: [MKAnnotation], edgePadding: UIEdgeInsets, animated: Bool) {
        guard !annotations.isEmpty else { return }

        if annotations.count == 1, let coordinate = annotations.first?.coordinate {
            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 250, longitudinalMeters: 250)
            setRegion(region, animated: animated)
            return
        }

        var zoomRect = MKMapRect.null
        for annotation in annotations {
            let point = MKMapPoint(annotation.coordinate)
            let rect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            zoomRect = zoomRect.isNull ? rect : zoomRect.union(rect)
        }

        zoomRect = mapRectThatFits(zoomRect)
        guard !zoomRect.isNull, !zoomRect.isEmpty else { return }

        setVisibleMapRect(zoomRect, edgePadding: edgePadding, animated: animated)
    }
}

/// Class to represent MKAnnotations on the map
class MapAnnotation: NSObject, MKAnnotation {
    /// The coordinate of the annotation
    let coordinate: CLLocationCoordinate2D

    /// The accuracy of the location
    let accuracy: Double

    /// The title of the annotation
    let title: String?

    /// The subtitle of the annotation
    let subtitle: String?

    /// Initializer using `ClusteredLocation`
    init(mapLocation: MapLocation) {
        /// Create new date formatter
        let dateFormatter = DateFormatter()

        /// Check if location has only been seen today - if yes, we do not need to show the date, but only the time
        if Calendar.current.isDateInToday(mapLocation.date) {
            dateFormatter.dateStyle = .none
        } else {
            dateFormatter.dateStyle = .short
        }

        /// Set the time and locale settings accordingly
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current

        /// Extract the coordinate from the clusteredLocation
        coordinate = mapLocation.location

        /// The string for the start date
        let dateString = dateFormatter.string(from: mapLocation.date)

        /// Create the title of the location - This is going to be the first time the tracker was seen at the location to the last time the tracker was seen at the location
        title = dateString

        /// Set the subtitle to the lowest accuracy for the location
        subtitle = "accuracy".localized() + ": \(Int(mapLocation.accuracy))m"

        accuracy = mapLocation.accuracy

        super.init()
    }
}

/// Extension to make CLLocationCoordinate2D conform to Equatable, Identifiable and Hashable
extension CLLocationCoordinate2D: @retroactive Equatable, @retroactive Hashable, @retroactive Identifiable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.id == rhs.id
    }

    public var id: String {
        "\(latitude)-\(longitude)"
    }
}

extension UIImage {
    /// Resizes an UIImage to a certain size
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
