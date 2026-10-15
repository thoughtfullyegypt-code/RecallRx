import SwiftUI

struct MedicalDiagramDefinition: Identifiable {
    let id: String
    let title: String
    let category: String
    let description: String
    let defaultMasks: [ImageOcclusionMask]
}

struct MedicalDiagramRegistry {
    static let diagrams: [MedicalDiagramDefinition] = [
        MedicalDiagramDefinition(
            id: "circle_of_willis",
            title: "Circle of Willis (Cerebrovascular)",
            category: "Neurology",
            description: "High-yield arterial circle; aneurysms cause subarachnoid hemorrhage and cranial neuropathies.",
            defaultMasks: [
                ImageOcclusionMask(id: 1, label: "Anterior Communicating Artery (ACoA)", x: 0.38, y: 0.16, width: 0.24, height: 0.08, hint: "Most common aneurysm site"),
                ImageOcclusionMask(id: 2, label: "Anterior Cerebral Artery (ACA)", x: 0.16, y: 0.22, width: 0.22, height: 0.08, hint: "Lower limb sensory/motor"),
                ImageOcclusionMask(id: 3, label: "Middle Cerebral Artery (MCA)", x: 0.04, y: 0.36, width: 0.22, height: 0.08, hint: "Upper limb & speech (Broca/Wernicke)"),
                ImageOcclusionMask(id: 4, label: "Internal Carotid Artery (ICA)", x: 0.28, y: 0.38, width: 0.20, height: 0.08, hint: "Cavernous sinus segment"),
                ImageOcclusionMask(id: 5, label: "Posterior Communicating Artery (PCoA)", x: 0.68, y: 0.44, width: 0.26, height: 0.08, hint: "Compresses CN III (blown pupil)"),
                ImageOcclusionMask(id: 6, label: "Posterior Cerebral Artery (PCA)", x: 0.64, y: 0.58, width: 0.26, height: 0.08, hint: "Homonymous hemianopsia (macular sparing)"),
                ImageOcclusionMask(id: 7, label: "Basilar Artery", x: 0.38, y: 0.72, width: 0.24, height: 0.08, hint: "Locked-in syndrome")
            ]
        ),
        MedicalDiagramDefinition(
            id: "cardiac_conduction",
            title: "Cardiac Conduction System",
            category: "Cardiology",
            description: "Electrical conduction pathway from SA node to ventricular Purkinje system.",
            defaultMasks: [
                ImageOcclusionMask(id: 1, label: "Sinoatrial (SA) Node", x: 0.14, y: 0.18, width: 0.26, height: 0.08, hint: "Primary cardiac pacemaker (60-100 bpm)"),
                ImageOcclusionMask(id: 2, label: "Atrioventricular (AV) Node", x: 0.38, y: 0.38, width: 0.24, height: 0.08, hint: "AV nodal delay (PR interval)"),
                ImageOcclusionMask(id: 3, label: "Bundle of His", x: 0.38, y: 0.52, width: 0.24, height: 0.08, hint: "Penetrates fibrous cardiac skeleton"),
                ImageOcclusionMask(id: 4, label: "Right & Left Bundle Branches", x: 0.30, y: 0.68, width: 0.40, height: 0.08, hint: "Interventricular septum conduction"),
                ImageOcclusionMask(id: 5, label: "Purkinje Fibers", x: 0.20, y: 0.84, width: 0.28, height: 0.08, hint: "Fastest ventricular propagation (4 m/s)")
            ]
        ),
        MedicalDiagramDefinition(
            id: "brachial_plexus",
            title: "Brachial Plexus Terminal Branches",
            category: "Anatomy",
            description: "C5-T1 nerve roots and the 5 major peripheral nerves of the upper extremity.",
            defaultMasks: [
                ImageOcclusionMask(id: 1, label: "Musculocutaneous Nerve (C5-C7)", x: 0.06, y: 0.24, width: 0.34, height: 0.08, hint: "Coracobrachialis, Biceps, Brachialis"),
                ImageOcclusionMask(id: 2, label: "Axillary Nerve (C5-C6)", x: 0.58, y: 0.24, width: 0.34, height: 0.08, hint: "Surgical neck fracture / Deltoid"),
                ImageOcclusionMask(id: 3, label: "Radial Nerve (C5-T1)", x: 0.58, y: 0.46, width: 0.34, height: 0.08, hint: "Midshaft humerus fracture / Wrist drop"),
                ImageOcclusionMask(id: 4, label: "Median Nerve (C5-T1)", x: 0.06, y: 0.62, width: 0.34, height: 0.08, hint: "Supracondylar fracture / Hand of Benediction"),
                ImageOcclusionMask(id: 5, label: "Ulnar Nerve (C8-T1)", x: 0.58, y: 0.74, width: 0.34, height: 0.08, hint: "Medial epicondyle fracture / Claw hand")
            ]
        )
    ]
}

struct MedicalDiagramCanvasView: View {
    let diagramId: String
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
            
            switch diagramId {
            case "circle_of_willis":
                circleOfWillisArt
            case "cardiac_conduction":
                cardiacConductionArt
            case "brachial_plexus":
                brachialPlexusArt
            default:
                defaultAnatomyArt
            }
        }
        .aspectRatio(1.2, contentMode: .fit)
    }
    
    // MARK: - Circle of Willis Vector Art
    private var circleOfWillisArt: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                // Brain silhouette outline
                Path { p in
                    p.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.05, width: w * 0.84, height: h * 0.90))
                }
                .stroke(Color.pink.opacity(0.12), lineWidth: 1.5)
                
                // Arteries Network
                Path { p in
                    // Basilar Artery (Vertical Trunk)
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.90))
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.66))
                    
                    // Vertebral Arteries merging
                    p.move(to: CGPoint(x: w * 0.36, y: h * 0.95))
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.90))
                    p.move(to: CGPoint(x: w * 0.64, y: h * 0.95))
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.90))
                    
                    // PCA Bifurcation
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.66))
                    p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.60))
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.66))
                    p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.60))
                    
                    // PCoA Connectors
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.60))
                    p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.42))
                    p.move(to: CGPoint(x: w * 0.70, y: h * 0.60))
                    p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.42))
                    
                    // Internal Carotids
                    p.move(to: CGPoint(x: w * 0.32, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w * 0.16, y: h * 0.38)) // MCA Left
                    p.move(to: CGPoint(x: w * 0.68, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.38)) // MCA Right
                    
                    // ACA branches
                    p.move(to: CGPoint(x: w * 0.32, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.22))
                    p.move(to: CGPoint(x: w * 0.68, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.22))
                    
                    // ACoA bridge
                    p.move(to: CGPoint(x: w * 0.42, y: h * 0.22))
                    p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.22))
                }
                .stroke(
                    LinearGradient(colors: [Color.red.opacity(0.85), Color.red], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
                
                // Optic Chiasm central landmark
                Path { p in
                    p.addEllipse(in: CGRect(x: w * 0.44, y: h * 0.32, width: w * 0.12, height: h * 0.08))
                }
                .fill(Color.orange.opacity(0.2))
                .overlay(
                    Text("Optic Chiasm")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .position(x: w * 0.50, y: h * 0.36)
                )
            }
        }
    }
    
    // MARK: - Cardiac Conduction Vector Art
    private var cardiacConductionArt: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                // Heart Chamber Contour
                Path { p in
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.90))
                    p.addCurve(to: CGPoint(x: w * 0.15, y: h * 0.35),
                               control1: CGPoint(x: w * 0.25, y: h * 0.70),
                               control2: CGPoint(x: w * 0.10, y: h * 0.50))
                    p.addArc(center: CGPoint(x: w * 0.32, y: h * 0.30), radius: w * 0.17, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                    p.addArc(center: CGPoint(x: w * 0.68, y: h * 0.30), radius: w * 0.17, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                    p.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.90),
                               control1: CGPoint(x: w * 0.90, y: h * 0.50),
                               control2: CGPoint(x: w * 0.75, y: h * 0.70))
                }
                .stroke(Color.red.opacity(0.2), lineWidth: 3)
                .background(
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.50, y: h * 0.90))
                        p.addCurve(to: CGPoint(x: w * 0.15, y: h * 0.35),
                                   control1: CGPoint(x: w * 0.25, y: h * 0.70),
                                   control2: CGPoint(x: w * 0.10, y: h * 0.50))
                        p.addArc(center: CGPoint(x: w * 0.32, y: h * 0.30), radius: w * 0.17, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                        p.addArc(center: CGPoint(x: w * 0.68, y: h * 0.30), radius: w * 0.17, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                        p.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.90),
                                   control1: CGPoint(x: w * 0.90, y: h * 0.50),
                                   control2: CGPoint(x: w * 0.75, y: h * 0.70))
                    }
                    .fill(Color.red.opacity(0.04))
                )
                
                // Conduction Fibers
                Path { p in
                    // Internodal Pathways
                    p.move(to: CGPoint(x: w * 0.28, y: h * 0.22)) // SA
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.42)) // AV
                    
                    // Bundle of His
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.56))
                    
                    // Right Bundle Branch
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.56))
                    p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.82))
                    
                    // Left Bundle Branch
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.56))
                    p.addLine(to: CGPoint(x: w * 0.65, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.82))
                }
                .stroke(
                    LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [6, 3])
                )
                
                // Nodes dots
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 14, height: 14)
                    .position(x: w * 0.28, y: h * 0.22)
                
                Circle()
                    .fill(Color.orange)
                    .frame(width: 14, height: 14)
                    .position(x: w * 0.50, y: h * 0.42)
            }
        }
    }
    
    // MARK: - Brachial Plexus Vector Art
    private var brachialPlexusArt: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                // Background Spinal Column representation
                Rectangle()
                    .fill(Color.purple.opacity(0.08))
                    .frame(width: w * 0.12, height: h * 0.86)
                    .position(x: w * 0.10, y: h * 0.50)
                
                Path { p in
                    // C5 - T1 Roots
                    let roots = [h * 0.18, h * 0.32, h * 0.46, h * 0.60, h * 0.74]
                    for y in roots {
                        p.move(to: CGPoint(x: w * 0.10, y: y))
                        p.addLine(to: CGPoint(x: w * 0.30, y: y))
                    }
                    
                    // Trunks
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.18))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.25)) // Upper
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.32))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.25))
                    
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.46))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.46)) // Middle
                    
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.60))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.67)) // Lower
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.74))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.67))
                    
                    // Terminal branch fans
                    p.move(to: CGPoint(x: w * 0.45, y: h * 0.25))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.20))
                    
                    p.move(to: CGPoint(x: w * 0.45, y: h * 0.46))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.46))
                    
                    p.move(to: CGPoint(x: w * 0.45, y: h * 0.67))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.72))
                }
                .stroke(
                    LinearGradient(colors: [Color.purple.opacity(0.8), Color.blue], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
    
    private var defaultAnatomyArt: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.artframe")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Medical Diagram Canvas")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
    }
}
