import SwiftUI

public struct ScoreView: View {
    public init() {}
    public var body: some View {
        Text("ScoreKit ScoreView")
            .font(.headline)
            .padding()
    }
}

#if DEBUG
struct ScoreView_Previews: PreviewProvider {
    static var previews: some View { ScoreView() }
}
#endif

