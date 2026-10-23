import SwiftUI

struct RatingButtonsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showNextReviewTime") private var showNextReviewTime = true

    let intervalStrings: [SM2Algorithm.Rating: String]
    let onRate: (SM2Algorithm.Rating) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize >= .xxxLarge ? 2 : 4)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SM2Algorithm.Rating.allCases) { rating in
                RatingButton(
                    rating: rating,
                    intervalText: showNextReviewTime ? intervalStrings[rating] : nil,
                    action: { onRate(rating) }
                )
            }
        }
    }
}
