import SwiftUI

/// Первое знакомство с приложением. Показывается один раз: экран входа и так
/// объясняет, куда человек попал, а длинный мастер из веба на телефоне только
/// занимает место.
struct OnboardingView: View {
    let onDone: () -> Void
    let onRegister: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "pawprint.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            VStack(spacing: 10) {
                Text("Petzy")
                    .font(.largeTitle.weight(.semibold))
                Text("Дневник питомца: записи, лекарства, медкарта и документы в одном месте")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                Button("Создать аккаунт", action: onRegister)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("У меня уже есть", action: onDone)
                    .controlSize(.large)
            }
        }
        .padding(32)
    }
}
