//
//  ContributorTypeLabel.swift
//  Spot
//
//  Created by Leon Böttger on 26.12.24.
//

import SwiftUI

func statusToString(_ status: LocationReport.Status, semanticLocation: String?, colorScheme: ColorScheme) -> LabelAndIcon {
    switch status {
    case .aggregated:
        LabelAndIcon(label: "High Traffic", icon: "person.3.fill", color: colorScheme.isLight ? .yellow : .orange)
    case .crowdsourced:
        LabelAndIcon(label: "All Areas", icon: "person.fill", color: .green)
    case .lastKnown:
        LabelAndIcon(label: "Own Report", icon: "smartphone", color: .green)
    case .semantic:
        LabelAndIcon(label: "\(semanticLocation ?? "Semantic Location")", icon: "house.fill", color: .green)
    case .UNRECOGNIZED:
        LabelAndIcon(label: "Unknown", icon: "questionmark", color: .red)
    }
}

struct LabelAndIcon {
    let label: String
    let icon: String
    let color: Color
}
