import Foundation
import SwiftData

struct SampleMedicalData {
    @MainActor
    static func loadSampleMedicalDeck(into modelContext: ModelContext) {
        // Loading examples is an explicit user action. A dedicated ID keeps the action
        // idempotent without guessing ownership from a user's deck name.
        let sampleDeckID = UUID(uuid: (0x52, 0x65, 0x63, 0x61, 0x6c, 0x6c, 0x52, 0x78,
                                      0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))
        let descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == sampleDeckID })
        guard let existing = try? modelContext.fetch(descriptor), existing.isEmpty else { return }
        let deckName = "USMLE Step 1 & 2 High-Yield"

        let deck = Deck(
            id: sampleDeckID,
            name: deckName,
            descriptionText: "High-yield USMLE Step 1 and Step 2 sample deck, with content-outline tags and collapsible study notes.",
            newCardsPerDay: 20,
            reviewsPerDay: 100
        )
        modelContext.insert(deck)
        
        // Card 1: Cardiology - Wolff-Parkinson-White (Suspended, UWorld QID 1052)
        let card1 = Card(
            front: "In {{c1::Wolff-Parkinson-White}} syndrome, the accessory electrical pathway is known as the {{c2::bundle of Kent}}, which bypasses the {{c3::AV node}}.",
            back: "ECG typically demonstrates a characteristic {{c4::delta wave}} with a shortened PR interval (<120 ms) and widened QRS complex.",
            deck: deck,
            tags: [
                "#USMLE::Cardiovascular::Arrhythmias",
                "#USMLE::Pathology::08_Cardiology::8.4_Arrhythmias",
                "#UWorld::Step1::Cardio::QID_1052"
            ],
            noteTypeRaw: NoteType.cloze.rawValue,
            isSuspended: true, // Suspended so user can test QBank Unsuspend!
            extra: "Wolff-Parkinson-White (WPW) is a congenital pre-excitation syndrome. Can lead to supraventricular tachycardia (PSVT) or atrial fibrillation with rapid ventricular response.",
            firstAid: "USMLE Content Outline · Cardiovascular · Short PR, delta wave, and a wide QRS. Ablation of the accessory pathway is definitive therapy.",
            sketchy: "Clinical pearl · Avoid AV nodal blockers in pre-excited atrial fibrillation. They can send conduction down the accessory pathway.",
            pathoma: "Chapter 8: Associated with congenital heart conditions including Ebstein anomaly.",
            clinicalPearls: "NBME Pearl: Hemodynamically unstable WPW gets immediate synchronized cardioversion. Stable AFib with WPW gets Procainamide or Ibutilide."
        )
        modelContext.insert(card1)
        
        // Card 2: Pathology - Myocardial Infarction Timelines (UWorld QID 2048)
        let card2 = Card(
            front: "What is the earliest histologic change seen {{c1::4 to 12 hours}} following an acute myocardial infarction?",
            back: "{{c1::Early coagulative necrosis, edema, and wavy myofibers}}.",
            deck: deck,
            tags: [
                "#USMLE::Cardiovascular::Pathology::MI",
                "#USMLE::Pathology::08_Cardiology::8.3_Myocardial_Infarction",
                "#UWorld::Step1::Biochem::QID_2048"
            ],
            noteTypeRaw: NoteType.medical.rawValue,
            isSuspended: true,
            extra: "Gross changes are minimal or absent during the first 4-12 hours (possible dark mottling). Troponin I and T become detectable in serum at 2-4 hours, peak at 24 hours.",
            firstAid: "USMLE Content Outline · Cardiovascular · Wavy fibers at 4–12 hours. Contraction bands appear early if the artery is reperfused.",
            sketchy: "Clinical pearl · The first day is dominated by arrhythmia, not by rupture.",
            pathoma: "Pathology outline · Heart · Arrhythmia in the first day. Macrophage-mediated rupture on days 3–7.",
            clinicalPearls: "Free wall rupture and papillary muscle rupture most commonly occur 3-14 days post-MI when granulation tissue and macrophages predominate."
        )
        modelContext.insert(card2)
        
        // Card 3: Pharmacology - Penicillin Mechanism & Resistance (UWorld QID 15302)
        let card3 = Card(
            front: "Penicillins and Cephalosporins exert their bactericidal action by binding to {{c1::penicillin-binding proteins (PBPs)}} and inhibiting the {{c2::transpeptidation}} step of cell wall synthesis.",
            back: "Bacterial resistance to Methicillin/Oxacillin is mediated by altered {{c3::PBP-2a}} encoded by the {{c4::mecA gene}}.",
            deck: deck,
            tags: [
                "#USMLE::Microbiology::Antimicrobials",
                "#USMLE::Pharmacology::Antimicrobials::Penicillins",
                "#UWorld::Step2::ID::QID_15302"
            ],
            noteTypeRaw: NoteType.cloze.rawValue,
            isSuspended: false,
            extra: "MRSA alters PBP binding affinity rather than producing beta-lactamase enzymes. Vancomycin or Daptomycin is required for treatment.",
            firstAid: "USMLE Content Outline · Pharmacology · Beta-lactams mimic D-Ala-D-Ala. Watch for immediate hypersensitivity and interstitial nephritis.",
            sketchy: "Clinical pearl · Beta-lactams bind penicillin-binding proteins and block peptidoglycan cross-linking.",
            pathoma: "Chapter 2: Drug-induced acute interstitial nephritis characterized by eosinophils in urine and fever/rash.",
            clinicalPearls: "Step 2 CK: MRSA bacteremia requires prompt echocardiogram to rule out infective endocarditis."
        )
        modelContext.insert(card3)
        
        // Card 4: Step 2 endocrinology — diabetic ketoacidosis (QID 1894)
        let card4 = Card(
            front: "In diabetic ketoacidosis (DKA), when serum potassium drops below {{c1::3.3 mEq/L}}, you must {{c2::hold insulin infusion}} and administer {{c3::IV potassium chloride}}.",
            back: "Total body potassium is {{c4::severely depleted}} even if serum potassium appears normal or elevated prior to insulin administration.",
            deck: deck,
            tags: [
                "#USMLE::Endocrinology::Diabetic_Ketoacidosis",
                "#USMLE::Endocrine::DKA",
                "#USMLE::Endocrine::QID_1894"
            ],
            noteTypeRaw: NoteType.cloze.rawValue,
            isSuspended: true,
            extra: "Insulin drives potassium into cells alongside glucose. Giving insulin with hypokalemia triggers lethal arrhythmias (VFib / asystole). Add dextrose when glucose < 200 mg/dL.",
            firstAid: "USMLE Content Outline · Endocrine · Anion-gap acidosis from ketones. Close the gap, not just the glucose.",
            sketchy: "Clinical pearl · Replace potassium before insulin when the serum potassium is below 3.3 mEq/L.",
            pathoma: "Chapter 17: Ketone bodies acetoacetate and beta-hydroxybutyrate formed from fatty acid breakdown.",
            clinicalPearls: "Step 2 CK Must-Know: The goal of DKA therapy is closure of the anion gap and correction of ketosis, NOT just normalizing blood glucose."
        )
        modelContext.insert(card4)
        
        // Card 5: Pediatrics — tetralogy of Fallot (QID 2190)
        let card5 = Card(
            front: "What four cardiac anomalies comprise Tetralogy of Fallot?",
            back: "1. {{c1::Pulmonary infundibular stenosis (most important for prognosis)}}\n2. {{c2::Right ventricular hypertrophy (boot-shaped heart)}}\n3. {{c3::Overriding aorta}}\n4. {{c4::Ventricular septal defect (VSD)}}",
            deck: deck,
            tags: [
                "#USMLE::Pediatrics::Tetralogy_of_Fallot",
                "#USMLE::Pathology::08_Cardiology::8.1_Congenital_Heart_Disease",
                "#USMLE::Pediatrics::QID_2190"
            ],
            noteTypeRaw: NoteType.medical.rawValue,
            isSuspended: false,
            extra: "Caused by anterosuperior displacement of the infundibular septum. Children squat during 'tet spells' to increase systemic vascular resistance (SVR), reversing the right-to-left shunt.",
            firstAid: "USMLE Content Outline · Cardiovascular · Pulmonary stenosis, right ventricular hypertrophy, an overriding aorta, and a VSD. Associated with 22q11 deletion.",
            sketchy: "Clinical pearl · Squatting raises systemic resistance and reduces the right-to-left shunt.",
            pathoma: "Pathology outline · Heart · Cyanosis tracks the degree of subpulmonic stenosis.",
            clinicalPearls: "Tet spell trigger: crying, feeding, exertion (decreased SVR). Treatment: knee-to-chest position, O2, IV morphine, phenylephrine."
        )
        modelContext.insert(card5)
        
        // Card 6: Neurology / Anatomy - Circle of Willis (Image Occlusion)
        let cowDiagram = MedicalDiagramRegistry.diagrams[0]
        let cowPayload = ImageOcclusionPayload(
            diagramId: cowDiagram.id,
            title: cowDiagram.title,
            masks: cowDiagram.defaultMasks,
            activeMaskId: 1, // ACoA
            mode: .hideAllGuessOne,
            clinicalNotes: "Anterior Communicating Artery (ACoA) is the most frequent location for saccular (berry) aneurysms. Rupture causes subarachnoid hemorrhage. Large aneurysms can cause bitemporal hemianopsia by compressing the central optic chiasm."
        )
        let card6 = Card(
            front: cowPayload.toJSON(),
            back: "Anterior Communicating Artery (ACoA)",
            deck: deck,
            tags: [
                "#USMLE::Neurology::Cerebrovascular",
                "#USMLE::Pathology::19_Neuro::Aneurysms",
                "#ImageOcclusion"
            ],
            noteTypeRaw: NoteType.imageOcclusion.rawValue,
            isSuspended: false,
            clinicalPearls: "ACoA aneurysm: Bitemporal hemianopsia (optic chiasm compression). PCoA aneurysm: Ipsilateral CN III palsy with mydriasis (blown pupil, 'down and out' eye)."
        )
        modelContext.insert(card6)
        
        // Save database
        try? modelContext.save()
    }
}
