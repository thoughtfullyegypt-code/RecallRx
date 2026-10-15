import Foundation
import SwiftData

struct SampleMedicalData {
    @MainActor
    static func loadSampleMedicalDeck(into modelContext: ModelContext) {
        // Clean up any test decks created by test runs
        if let leftoverDecks = try? modelContext.fetch(FetchDescriptor<Deck>()) {
            for d in leftoverDecks where d.name.contains("Test Deck") || d.name.contains("Test Parent") {
                modelContext.delete(d)
            }
        }
        
        // Create or find high-yield deck
        let deckName = "AnKing Step 1 & 2 High-Yield"
        let deckDescriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.name == deckName })
        if let existing = try? modelContext.fetch(deckDescriptor), let existingDeck = existing.first {
            if !existingDeck.cards.contains(where: { $0.noteTypeRaw == NoteType.imageOcclusion.rawValue }) {
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
                    deck: existingDeck,
                    tags: [
                        "#AK_Step1_v12::#FirstAid::Neurology::Cerebrovascular",
                        "#AK_Step1_v12::#Pathoma::19_Neuro::Aneurysms",
                        "#ImageOcclusion"
                    ],
                    noteTypeRaw: NoteType.imageOcclusion.rawValue,
                    isSuspended: false,
                    clinicalPearls: "ACoA aneurysm: Bitemporal hemianopsia (optic chiasm compression). PCoA aneurysm: Ipsilateral CN III palsy with mydriasis (blown pupil, 'down and out' eye)."
                )
                card6.fsrsStability = 8.4
                card6.fsrsDifficulty = 4.8
                card6.fsrsReps = 2
                modelContext.insert(card6)
                try? modelContext.save()
            }
            return
        }
        
        let deck = Deck(
            name: deckName,
            descriptionText: "High-Yield USMLE Step 1 & 2 Sample Deck with AnKing tags, QBank QIDs, and collapsible resource fields.",
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
                "#AK_Step1_v12::#FirstAid::Cardiovascular::Arrhythmias",
                "#AK_Step1_v12::#Pathoma::08_Cardiology::8.4_Arrhythmias",
                "#UWorld::Step1::Cardio::QID_1052"
            ],
            noteTypeRaw: NoteType.cloze.rawValue,
            isSuspended: true, // Suspended so user can test QBank Unsuspend!
            extra: "Wolff-Parkinson-White (WPW) is a congenital pre-excitation syndrome. Can lead to supraventricular tachycardia (PSVT) or atrial fibrillation with rapid ventricular response.",
            firstAid: "First Aid 2024 p. 298: Triad of short PR interval, widened QRS, and delta wave. Catheter ablation of the accessory pathway is definitive curative therapy.",
            sketchy: "SketchyPharm Antiarrhythmics: Avoid AV nodal blocking agents (ABCD: Adenosine, Beta-blockers, CCBs, Digoxin) which can direct conduction down accessory pathway and precipitate VFib!",
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
                "#AK_Step1_v12::#FirstAid::Cardiovascular::Pathology::MI",
                "#AK_Step1_v12::#Pathoma::08_Cardiology::8.3_Myocardial_Infarction",
                "#UWorld::Step1::Biochem::QID_2048"
            ],
            noteTypeRaw: NoteType.medical.rawValue,
            isSuspended: true,
            extra: "Gross changes are minimal or absent during the first 4-12 hours (possible dark mottling). Troponin I and T become detectable in serum at 2-4 hours, peak at 24 hours.",
            firstAid: "First Aid 2024 p. 312: Comprehensive MI Timeline table. Contraction bands also visible at 1-4 hours if reperfusion occurs.",
            sketchy: "SketchyPath Cardiac: Remember the wavy fibers waving hello at 4-12 hours!",
            pathoma: "Pathoma Chapter 8: Key complication within first 24 hours is fatal ventricular arrhythmias. Macrophage rupture occurs days 3-7.",
            clinicalPearls: "Free wall rupture and papillary muscle rupture most commonly occur 3-14 days post-MI when granulation tissue and macrophages predominate."
        )
        modelContext.insert(card2)
        
        // Card 3: Pharmacology - Penicillin Mechanism & Resistance (UWorld QID 15302)
        let card3 = Card(
            front: "Penicillins and Cephalosporins exert their bactericidal action by binding to {{c1::penicillin-binding proteins (PBPs)}} and inhibiting the {{c2::transpeptidation}} step of cell wall synthesis.",
            back: "Bacterial resistance to Methicillin/Oxacillin is mediated by altered {{c3::PBP-2a}} encoded by the {{c4::mecA gene}}.",
            deck: deck,
            tags: [
                "#AK_Step1_v12::#FirstAid::Microbiology::Antimicrobials",
                "#AK_Step1_v12::#SketchyPharm::Antimicrobials::Penicillins",
                "#UWorld::Step2::ID::QID_15302"
            ],
            noteTypeRaw: NoteType.cloze.rawValue,
            isSuspended: false,
            extra: "MRSA alters PBP binding affinity rather than producing beta-lactamase enzymes. Vancomycin or Daptomycin is required for treatment.",
            firstAid: "First Aid 2024 p. 188: D-Ala-D-Ala structural analog. Hypersensitivity reactions (Type I IgE) and interstitial nephritis are classic adverse effects.",
            sketchy: "SketchyPharm Micro: The royal knights forging peptidoglycan shields with PBP hammers.",
            pathoma: "Chapter 2: Drug-induced acute interstitial nephritis characterized by eosinophils in urine and fever/rash.",
            clinicalPearls: "Step 2 CK: MRSA bacteremia requires prompt echocardiogram to rule out infective endocarditis."
        )
        card3.fsrsStability = 12.5
        card3.fsrsDifficulty = 4.2
        card3.fsrsReps = 3
        modelContext.insert(card3)
        
        // Card 4: Step 2 CK Endocrinology - Diabetic Ketoacidosis (AMBOSS QID 1894)
        let card4 = Card(
            front: "In diabetic ketoacidosis (DKA), when serum potassium drops below {{c1::3.3 mEq/L}}, you must {{c2::hold insulin infusion}} and administer {{c3::IV potassium chloride}}.",
            back: "Total body potassium is {{c4::severely depleted}} even if serum potassium appears normal or elevated prior to insulin administration.",
            deck: deck,
            tags: [
                "#AK_Step2_v12::#Amboss::Endocrinology::Diabetic_Ketoacidosis",
                "#AK_Step2_v12::#FirstAid_Step2::Endocrine::DKA",
                "#AMBOSS::Step1::Pathology::QID_1894"
            ],
            noteTypeRaw: NoteType.cloze.rawValue,
            isSuspended: true,
            extra: "Insulin drives potassium into cells alongside glucose. Giving insulin with hypokalemia triggers lethal arrhythmias (VFib / asystole). Add dextrose when glucose < 200 mg/dL.",
            firstAid: "First Aid Step 2 CK p. 340: Anion gap metabolic acidosis: DKA, Uremia, Lactic acidosis, Methanol, Ethylene glycol.",
            sketchy: "SketchyMed Endocrine: Banana IV bags hanging before the insulin syringe strikes.",
            pathoma: "Chapter 17: Ketone bodies acetoacetate and beta-hydroxybutyrate formed from fatty acid breakdown.",
            clinicalPearls: "Step 2 CK Must-Know: The goal of DKA therapy is closure of the anion gap and correction of ketosis, NOT just normalizing blood glucose."
        )
        modelContext.insert(card4)
        
        // Card 5: Pediatrics - Tetralogy of Fallot (AMBOSS QID 2190)
        let card5 = Card(
            front: "What four cardiac anomalies comprise Tetralogy of Fallot?",
            back: "1. {{c1::Pulmonary infundibular stenosis (most important for prognosis)}}\n2. {{c2::Right ventricular hypertrophy (boot-shaped heart)}}\n3. {{c3::Overriding aorta}}\n4. {{c4::Ventricular septal defect (VSD)}}",
            deck: deck,
            tags: [
                "#AK_Step1_v12::#FirstAid::Pediatrics::Tetralogy_of_Fallot",
                "#AK_Step1_v12::#Pathoma::08_Cardiology::8.1_Congenital_Heart_Disease",
                "#AMBOSS::Step2::Peds::QID_2190"
            ],
            noteTypeRaw: NoteType.medical.rawValue,
            isSuspended: false,
            extra: "Caused by anterosuperior displacement of the infundibular septum. Children squat during 'tet spells' to increase systemic vascular resistance (SVR), reversing the right-to-left shunt.",
            firstAid: "First Aid 2024 p. 290: PROVe mnemonic: Pulmonary stenosis, RVH, Overriding aorta, VSD. Associated with 22q11 deletion (DiGeorge syndrome).",
            sketchy: "SketchyPath Peds: The four cowboys around the campfire with the boot on the fence.",
            pathoma: "Pathoma Chapter 8: Severity of cyanosis depends directly on degree of subpulmonic stenosis.",
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
                "#AK_Step1_v12::#FirstAid::Neurology::Cerebrovascular",
                "#AK_Step1_v12::#Pathoma::19_Neuro::Aneurysms",
                "#ImageOcclusion"
            ],
            noteTypeRaw: NoteType.imageOcclusion.rawValue,
            isSuspended: false,
            clinicalPearls: "ACoA aneurysm: Bitemporal hemianopsia (optic chiasm compression). PCoA aneurysm: Ipsilateral CN III palsy with mydriasis (blown pupil, 'down and out' eye)."
        )
        card6.fsrsStability = 8.4
        card6.fsrsDifficulty = 4.8
        card6.fsrsReps = 2
        modelContext.insert(card6)
        
        // Save database
        try? modelContext.save()
    }
}
