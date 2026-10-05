//  The strip above the composer while the assistant looks over a message, and
//  its verdict: send anyway, use a better version, or keep editing.

import SwiftUI
import NodogramDomain
import NodogramUI

struct DraftReviewBar: View {
    let model: AppModel
    let review: DraftReview

    var body: some View {
        Group {
            switch review.state {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking your message…").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Send Anyway") { model.sendDespiteReview() }.controlSize(.small)
                }
            case .failed(let why):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                    Text("Couldn't check (\(why)).").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Send") { model.sendDespiteReview() }.controlSize(.small).buttonStyle(.borderedProminent)
                    Button("Keep Editing") { model.dismissReview() }.controlSize(.small)
                }
            case .result(let verdict, let reason, let improved):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: verdict == "hold" ? "hand.raised.fill" : "pencil.and.outline")
                            .foregroundStyle(verdict == "hold" ? Theme.failure : Theme.warning)
                        Text(reason).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    if !improved.isEmpty, improved != review.text {
                        Text(improved).font(.system(size: 12.5)).italic().foregroundStyle(.secondary)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                    }
                    HStack {
                        Spacer()
                        Button("Keep Editing") { model.dismissReview() }.controlSize(.small)
                        if !improved.isEmpty, improved != review.text {
                            Button("Use Suggestion") { model.useImprovedDraft() }.controlSize(.small)
                        }
                        Button("Send Anyway") { model.sendDespiteReview() }.controlSize(.small).buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.warning.opacity(0.08))
        .overlay(alignment: .top) { Divider() }
    }
}
