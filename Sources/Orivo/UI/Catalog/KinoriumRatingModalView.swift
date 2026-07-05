import SwiftUI

public struct KinoriumRatingModalView: View {
    let target: KinoriumRatingTarget
    @Environment(\.dismiss) var dismiss
    
    @State private var rating: Int = 0 // 0 means no rating selected
    @State private var comment: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    public init(target: KinoriumRatingTarget) {
        self.target = target
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Оценить просмотр")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(target.title)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 24)
            
            // Rating selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Ваша оценка (1-10)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 24)
                
                HStack(spacing: 6) {
                    ForEach(1...10, id: \.self) { num in
                        Button(action: {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                rating = num
                            }
                        }) {
                            Text("\(num)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(rating == num ? .white : ratingColor(for: num).opacity(0.8))
                                .frame(width: 34, height: 34)
                                .background(
                                    ZStack {
                                        if rating == num {
                                            ratingColor(for: num)
                                                .cornerRadius(8)
                                                .shadow(color: ratingColor(for: num).opacity(0.5), radius: 6)
                                        } else {
                                            Color.white.opacity(0.04)
                                                .cornerRadius(8)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(ratingColor(for: num).opacity(0.25), lineWidth: 1)
                                                )
                                        }
                                    }
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
            }
            
            // Comment input
            VStack(alignment: .leading, spacing: 8) {
                Text("Комментарий или отзыв (необязательно)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 24)
                
                ZStack(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("Напишите ваше мнение о фильме...")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $comment)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(4)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
            }
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 24)
            
            // Footer Buttons
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Пропустить")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoading)
                
                Button(action: { submitRating() }) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Отправить в Кинориум")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    private func ratingColor(for num: Int) -> Color {
        switch num {
        case 1...4:
            return Color.red
        case 5...7:
            return Color.orange
        default:
            return Color.green
        }
    }
    
    private func submitRating() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await KinoriumClient.shared.setMovieStatus(
                    movieID: target.kinoriumID,
                    status: .watched,
                    rating: rating > 0 ? rating : nil,
                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment
                )
                
                LogManager.shared.log(serviceId: "system", text: "KinoriumRatingModalView: Rating and comment successfully sent to Kinorium!")
                AppStateManager.shared.showHUD(message: "Кинориум: Оценка отправлена!", isSuccess: true)
                isLoading = false
                dismiss()
            } catch {
                LogManager.shared.log(serviceId: "system", text: "KinoriumRatingModalView: Submit failed: \(error.localizedDescription)", isError: true)
                AppStateManager.shared.showHUD(message: "Кинориум: Ошибка отправки оценки", isSuccess: false)
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
