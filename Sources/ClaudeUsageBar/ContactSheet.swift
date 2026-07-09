import SwiftUI

/// 문의하기 — 별도 Window로 표시(MenuBarExtra .sheet은 텍스트 포커스 시 패널이 닫혀버림).
struct ContactWindowView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var message = ""
    @State private var sender = ""
    @State private var sending = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("문의하기").font(.headline)
            Text("내용이 담당 Dooray 방으로 전송됩니다. (앱 버전·OS 자동 첨부)")
                .font(.caption).foregroundStyle(.secondary)
            TextField("보내는 사람 (선택)", text: $sender).textFieldStyle(.roundedBorder)
            TextEditor(text: $message)
                .frame(height: 140).border(.secondary.opacity(0.3))
            if let r = result {
                Text(r).font(.caption).foregroundStyle(r.contains("완료") ? .green : .red)
            }
            HStack {
                Spacer()
                Button("닫기") { dismissWindow(id: "contact") }
                Button(sending ? "전송 중…" : "보내기") {
                    sending = true; result = nil
                    Task {
                        let ok = await state.sendContact(message: message, from: sender)
                        sending = false
                        result = ok ? "전송 완료" : "전송 실패 — 잠시 후 다시 시도"
                        if ok {
                            try? await Task.sleep(for: .seconds(1))
                            message = ""; sender = ""; result = nil   // 다음에 열 때 빈 폼(창 인스턴스 재사용됨)
                            dismissWindow(id: "contact")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
